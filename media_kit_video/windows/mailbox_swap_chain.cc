// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright (c) 2026 Predidit.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "mailbox_swap_chain.h"

#include <chrono>
#include <iostream>
#include <new>

#include "performance_metrics.h"

MailboxSwapChain::~MailboxSwapChain() {
  ReleaseSlots();
  if (fence_event_) {
    ::CloseHandle(fence_event_);
    fence_event_ = nullptr;
  }
}

HRESULT MailboxSwapChain::Create(ID3D11Device* device,
                                  int32_t width,
                                  int32_t height,
                                  bool non_blocking,
                                  MailboxSwapChain** out) {
  if (!device || !out) return E_INVALIDARG;

  auto* p = new (std::nothrow) MailboxSwapChain();
  if (!p) return E_OUTOFMEMORY;

  p->device_ = device;
  p->width_ = width > 0 ? width : 1;
  p->height_ = height > 0 ? height : 1;
  p->non_blocking_ = non_blocking;
  if (non_blocking) {
    p->ResetNonBlockingState();
  }
  p->fence_event_ = ::CreateEvent(nullptr, FALSE, FALSE, nullptr);
  if (!p->fence_event_) {
    const DWORD error = ::GetLastError();
    delete p;
    return HRESULT_FROM_WIN32(error);
  }

  Microsoft::WRL::ComPtr<ID3D11DeviceContext> ctx;
  device->GetImmediateContext(&ctx);
  const HRESULT context_hr = ctx.As(&p->context4_);
  if (FAILED(context_hr)) {
    std::cout << "media_kit: MailboxSwapChain: ID3D11DeviceContext4 not "
                 "available (hr=0x"
              << std::hex << context_hr << std::dec << ")" << std::endl;
    delete p;
    return context_hr;
  }

  const HRESULT hr = p->AllocateSlots();
  if (FAILED(hr)) {
    delete p;
    return hr;
  }

  *out = p;
  return S_OK;
}

HRESULT STDMETHODCALLTYPE MailboxSwapChain::QueryInterface(REFIID riid,
                                                            void** ppv) {
  if (!ppv) return E_POINTER;

  if (riid == __uuidof(IUnknown) || riid == __uuidof(IDXGIObject) ||
      riid == __uuidof(IDXGIDeviceSubObject) ||
      riid == __uuidof(IDXGISwapChain)) {
    *ppv = static_cast<IDXGISwapChain*>(this);
    AddRef();
    return S_OK;
  }

  *ppv = nullptr;
  return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE MailboxSwapChain::AddRef() {
  return ref_count_.fetch_add(1u, std::memory_order_relaxed) + 1u;
}

ULONG STDMETHODCALLTYPE MailboxSwapChain::Release() {
  const ULONG prev = ref_count_.fetch_sub(1u, std::memory_order_acq_rel);
  if (prev == 1u) delete this;
  return prev - 1u;
}

HRESULT STDMETHODCALLTYPE MailboxSwapChain::GetBuffer(UINT Buffer,
                                                       REFIID riid,
                                                       void** ppSurface) {
  if (!ppSurface) return E_POINTER;
  if (Buffer != 0) return DXGI_ERROR_INVALID_CALL;
  if (riid != __uuidof(ID3D11Texture2D) &&
      riid != __uuidof(ID3D11Resource)) {
    return E_NOINTERFACE;
  }

  ID3D11Texture2D* tex = RenderTarget();
  if (!tex) return E_FAIL;

  tex->AddRef();
  *ppSurface = tex;
  return S_OK;
}

HRESULT STDMETHODCALLTYPE MailboxSwapChain::GetDesc(DXGI_SWAP_CHAIN_DESC* desc) {
  if (!desc) return E_POINTER;
  *desc = {};
  desc->BufferDesc.Width = static_cast<UINT>(width_);
  desc->BufferDesc.Height = static_cast<UINT>(height_);
  desc->BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc->BufferCount = 1;
  desc->SampleDesc.Count = 1;
  desc->BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT | DXGI_USAGE_SHADER_INPUT;
  desc->Windowed = TRUE;
  desc->SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
  return S_OK;
}

ID3D11Texture2D* MailboxSwapChain::RenderTarget() {
  if (non_blocking_) {
    std::lock_guard<std::mutex> lock(slots_mutex_);
    return RenderTargetNonBlocking();
  }

  std::lock_guard<std::mutex> lock(slots_mutex_);

  if (write_slot_ >= 0) {
    return slots_[write_slot_].texture.Get();
  }

  write_slot_ = next_write_slot_;
  return slots_[write_slot_].texture.Get();
}

bool MailboxSwapChain::ProducerCommit() {
  if (non_blocking_) {
    std::lock_guard<std::mutex> lock(slots_mutex_);
    return ProducerCommitNonBlocking();
  }

  int submitted_slot = -1;
  {
    std::lock_guard<std::mutex> lock(slots_mutex_);

    submitted_slot = write_slot_;
    if (submitted_slot < 0) {
      media_kit_video::PerformanceMetrics::Instance()
          .AddProducerCommitFailure();
      return false;
    }

    auto& slot = slots_[submitted_slot];
    if (!slot.fence) {
      media_kit_video::PerformanceMetrics::Instance()
          .AddProducerCommitFailure();
      return false;
    }

    const HRESULT signal_hr =
        context4_->Signal(slot.fence.Get(), ++slot.fence_value);
    if (FAILED(signal_hr)) {
      write_slot_ = -1;
      media_kit_video::PerformanceMetrics::Instance()
          .AddProducerCommitFailure();
      return false;
    }

    context4_->Flush();
    media_kit_video::PerformanceMetrics::Instance().AddFlush();
    write_slot_ = -1;
  }

  // Do not hold the mailbox mutex while waiting for the GPU. Flutter can keep
  // consuming the most recently completed texture instead of blocking its
  // render thread behind the producer.
  const HRESULT hr = WaitForSlot(submitted_slot);
  if (FAILED(hr)) {
    media_kit_video::PerformanceMetrics::Instance()
        .AddProducerCommitFailure();
    return false;
  }

  {
    std::lock_guard<std::mutex> lock(slots_mutex_);
    latest_completed_slot_.store(submitted_slot, std::memory_order_release);
    has_completed_frame_.store(true, std::memory_order_release);
    next_write_slot_ = (submitted_slot + 1) % 4;
  }
  media_kit_video::PerformanceMetrics::Instance().AddPublish();
  return true;
}

HANDLE MailboxSwapChain::ConsumerAcquire() {
  std::lock_guard<std::mutex> lock(slots_mutex_);
  if (!has_completed_frame_.load(std::memory_order_acquire)) return nullptr;

  const int slot = latest_completed_slot_.load(std::memory_order_acquire);
  if (slot < 0) return nullptr;

  return slots_[slot].shared_handle;
}

void MailboxSwapChain::ConsumerRelease(HANDLE handle) {
  if (!non_blocking_ || !handle) return;

  std::lock_guard<std::mutex> lock(slots_mutex_);
  const int published =
      latest_completed_slot_.load(std::memory_order_acquire);
  if (published < 0 || slots_[published].shared_handle != handle) return;

  // Flutter invokes the descriptor release callback after opening |handle| and
  // releasing its previously bound EGL image. Only now may older published
  // textures be rendered into again.
  for (auto& slot : slots_) {
    if (slot.state == SlotState::kRetired) {
      slot.state = SlotState::kFree;
    }
  }
}

HANDLE MailboxSwapChain::ReadHandleSnapshot() {
  std::lock_guard<std::mutex> lock(slots_mutex_);
  if (!has_completed_frame_.load(std::memory_order_acquire)) return nullptr;

  const int slot = latest_completed_slot_.load(std::memory_order_acquire);
  if (slot < 0) return nullptr;

  return slots_[slot].shared_handle;
}

HRESULT MailboxSwapChain::Resize(int32_t width, int32_t height) {
  std::lock_guard<std::mutex> lock(slots_mutex_);
  ReleaseSlots();
  width_ = width > 0 ? width : 1;
  height_ = height > 0 ? height : 1;
  has_completed_frame_.store(false, std::memory_order_release);
  if (non_blocking_) {
    ResetNonBlockingState();
  } else {
    latest_completed_slot_.store(-1, std::memory_order_release);
    next_write_slot_ = 0;
    write_slot_ = -1;
  }
  return AllocateSlots();
}

HRESULT MailboxSwapChain::AllocateSlots() {
  Microsoft::WRL::ComPtr<ID3D11Device5> device5;
  HRESULT hr = device_->QueryInterface(IID_PPV_ARGS(device5.GetAddressOf()));
  if (FAILED(hr)) {
    std::cout << "media_kit: MailboxSwapChain: ID3D11Device5 not available "
                 "(hr=0x"
              << std::hex << hr << std::dec << ")" << std::endl;
    return hr;
  }

  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = static_cast<UINT>(width_);
  desc.Height = static_cast<UINT>(height_);
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.SampleDesc.Quality = 0;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  desc.CPUAccessFlags = 0;
  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

  for (int i = 0; i < 4; ++i) {
    hr = device_->CreateTexture2D(&desc, nullptr, &slots_[i].texture);
    if (FAILED(hr)) return hr;

    Microsoft::WRL::ComPtr<IDXGIResource> resource;
    hr = slots_[i].texture.As(&resource);
    if (FAILED(hr)) return hr;

    hr = resource->GetSharedHandle(&slots_[i].shared_handle);
    if (FAILED(hr)) return hr;

    hr = device5->CreateFence(0, D3D11_FENCE_FLAG_NONE,
                              IID_PPV_ARGS(slots_[i].fence.GetAddressOf()));
    if (FAILED(hr)) return hr;
    slots_[i].fence_value = 0;
  }

  return S_OK;
}

bool MailboxSwapChain::ProducerCommitNonBlocking() {
  if (write_slot_ < 0) {
    PromoteCompletedFrames();
    return TakePublishedFrame();
  }

  const int submitted_slot = write_slot_;
  const bool needs_first_frame =
      !has_completed_frame_.load(std::memory_order_acquire);
  auto& write = slots_[submitted_slot];
  const HRESULT signal_hr =
      context4_->Signal(write.fence.Get(), ++write.fence_value);
  if (FAILED(signal_hr)) {
    write.state = SlotState::kFree;
    write_slot_ = -1;
    media_kit_video::PerformanceMetrics::Instance()
        .AddProducerCommitFailure();
    return TakePublishedFrame();
  }

  write.submission_id = ++next_submission_id_;
  write.state = SlotState::kPending;
  write_slot_ = -1;

  // Flush submits the fence but does not wait for it. Without this, a full
  // mailbox can stop issuing D3D work before the queued fences become visible.
  context4_->Flush();
  media_kit_video::PerformanceMetrics::Instance().AddFlush();

  // Flutter has no valid surface immediately after a texture rebuild. Wait
  // only for that first frame so a resize never exposes an empty/black frame;
  // steady-state publication remains fully non-blocking.
  if (needs_first_frame && FAILED(WaitForSlot(submitted_slot))) {
    return false;
  }
  PromoteCompletedFrames();
  return TakePublishedFrame();
}

ID3D11Texture2D* MailboxSwapChain::RenderTargetNonBlocking() {
  if (write_slot_ >= 0) {
    return slots_[write_slot_].texture.Get();
  }

  PromoteCompletedFrames();
  for (int slot = 0; slot < 4; ++slot) {
    if (slots_[slot].state == SlotState::kFree) {
      slots_[slot].state = SlotState::kWriting;
      write_slot_ = slot;
      return slots_[slot].texture.Get();
    }
  }

  media_kit_video::PerformanceMetrics::Instance().AddMailboxFull();
  return nullptr;
}

bool MailboxSwapChain::PromoteCompletedFrames() {
  int newest_completed = -1;
  uint64_t newest_submission = 0;
  bool completed[4] = {};
  uint64_t pending_count = 0;

  for (int slot = 0; slot < 4; ++slot) {
    const auto& candidate = slots_[slot];
    if (candidate.state != SlotState::kPending || !candidate.fence) {
      continue;
    }
    ++pending_count;
    media_kit_video::PerformanceMetrics::Instance()
        .AddNonBlockingFencePoll();
    completed[slot] =
        candidate.fence->GetCompletedValue() >= candidate.fence_value;
    if (!completed[slot]) {
      media_kit_video::PerformanceMetrics::Instance()
          .AddNonBlockingFenceIncomplete();
      continue;
    }
    if (newest_completed < 0 ||
        candidate.submission_id > newest_submission) {
      newest_completed = slot;
      newest_submission = candidate.submission_id;
    }
  }
  if (newest_completed < 0) {
    media_kit_video::PerformanceMetrics::Instance().SetPendingSlots(
        pending_count);
    return false;
  }

  const int previously_published =
      latest_completed_slot_.load(std::memory_order_acquire);
  if (previously_published >= 0 && previously_published != newest_completed &&
      slots_[previously_published].state == SlotState::kPublished) {
    slots_[previously_published].state = SlotState::kRetired;
  }

  for (int slot = 0; slot < 4; ++slot) {
    auto& candidate = slots_[slot];
    if (candidate.state == SlotState::kPending && completed[slot]) {
      candidate.state =
          slot == newest_completed ? SlotState::kPublished : SlotState::kFree;
    }
  }

  uint64_t remaining_pending = 0;
  for (const auto& slot : slots_) {
    if (slot.state == SlotState::kPending) ++remaining_pending;
  }
  media_kit_video::PerformanceMetrics::Instance().SetPendingSlots(
      remaining_pending);

  latest_completed_slot_.store(newest_completed, std::memory_order_release);
  has_completed_frame_.store(true, std::memory_order_release);
  published_frame_pending_ = true;
  media_kit_video::PerformanceMetrics::Instance().AddPublish();
  return true;
}

bool MailboxSwapChain::TakePublishedFrame() {
  const bool result = published_frame_pending_;
  published_frame_pending_ = false;
  return result;
}

void MailboxSwapChain::ResetNonBlockingState() {
  next_submission_id_ = 0;
  published_frame_pending_ = false;
  write_slot_ = -1;
  // A newly allocated texture is not a frame. Keep every handle unpublished
  // until its first render fence completes to avoid exposing a black resize.
  has_completed_frame_.store(false, std::memory_order_release);
  latest_completed_slot_.store(-1, std::memory_order_release);
  for (auto& slot : slots_) {
    slot.submission_id = 0;
    slot.state = SlotState::kFree;
  }
  media_kit_video::PerformanceMetrics::Instance().SetPendingSlots(0);
}

HRESULT MailboxSwapChain::WaitForSlot(int slot) {
  if (slot < 0 || slot >= 4) return E_INVALIDARG;

  auto& texture_slot = slots_[slot];
  if (!texture_slot.fence || texture_slot.fence_value == 0) return E_FAIL;
  if (texture_slot.fence->GetCompletedValue() >= texture_slot.fence_value) {
    return S_OK;
  }

  auto& metrics = media_kit_video::PerformanceMetrics::Instance();
  const bool collect_metrics = metrics.enabled();
  std::chrono::steady_clock::time_point start;
  if (collect_metrics) start = std::chrono::steady_clock::now();
  metrics.AddBlockingFenceWait();

  HRESULT hr = texture_slot.fence->SetEventOnCompletion(
      texture_slot.fence_value, fence_event_);
  if (FAILED(hr)) return hr;

  const DWORD wait = ::WaitForSingleObject(fence_event_, INFINITE);
  if (collect_metrics) {
    const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now() - start);
    metrics.ObserveBlockingWaitDuration(
        static_cast<uint64_t>(elapsed.count() < 0 ? 0 : elapsed.count()));
  }
  return wait == WAIT_OBJECT_0 ? S_OK : HRESULT_FROM_WIN32(::GetLastError());
}

void MailboxSwapChain::ReleaseSlots() {
  for (auto& slot : slots_) {
    slot.texture.Reset();
    slot.shared_handle = nullptr;
    slot.fence.Reset();
    slot.fence_value = 0;
    slot.submission_id = 0;
    slot.state = SlotState::kFree;
  }
}

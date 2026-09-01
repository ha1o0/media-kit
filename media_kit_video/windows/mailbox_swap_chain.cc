// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright (c) 2026 Predidit.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "mailbox_swap_chain.h"

#include <iostream>
#include <limits>
#include <new>
#include <system_error>
#include <utility>

namespace {

constexpr uint64_t kFenceDeviceRemovedValue = ~uint64_t{0};

bool IsFenceComplete(ID3D11Fence* fence, uint64_t value) {
  if (!fence) return false;
  const uint64_t completed = fence->GetCompletedValue();
  return completed != kFenceDeviceRemovedValue && completed >= value;
}

}  // namespace

MailboxSwapChain::~MailboxSwapChain() {
  StopCompletionThread();
  ReleaseSlots();
  if (fence_event_) {
    ::CloseHandle(fence_event_);
    fence_event_ = nullptr;
  }
  if (completion_stop_event_) {
    ::CloseHandle(completion_stop_event_);
    completion_stop_event_ = nullptr;
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
  if (non_blocking) {
    p->completion_stop_event_ = ::CreateEvent(nullptr, TRUE, FALSE, nullptr);
    if (!p->completion_stop_event_) {
      const DWORD error = ::GetLastError();
      delete p;
      return HRESULT_FROM_WIN32(error);
    }
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
  if (non_blocking) {
    try {
      p->StartCompletionThread();
    } catch (const std::system_error& error) {
      std::cout << "media_kit: MailboxSwapChain: failed to start completion "
                   "thread: "
                << error.what() << std::endl;
      delete p;
      return E_FAIL;
    }
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
      return false;
    }

    auto& slot = slots_[submitted_slot];
    if (!slot.fence) return false;

    const HRESULT signal_hr =
        context4_->Signal(slot.fence.Get(), ++slot.fence_value);
    if (FAILED(signal_hr)) {
      write_slot_ = -1;
      return false;
    }

    context4_->Flush();
    write_slot_ = -1;
  }

  // Do not hold the mailbox mutex while waiting for the GPU. Flutter can keep
  // consuming the most recently completed texture instead of blocking its
  // render thread behind the producer.
  const HRESULT hr = WaitForSlot(submitted_slot);
  if (FAILED(hr)) {
    std::cout << "media_kit: MailboxSwapChain: blocking fence wait failed "
                 "(hr=0x"
              << std::hex << hr << std::dec << ")" << std::endl;
    std::lock_guard<std::mutex> lock(slots_mutex_);
    next_write_slot_ = (submitted_slot + 1) % 4;
    return false;
  }

  {
    std::lock_guard<std::mutex> lock(slots_mutex_);
    latest_completed_slot_.store(submitted_slot, std::memory_order_release);
    has_completed_frame_.store(true, std::memory_order_release);
    next_write_slot_ = (submitted_slot + 1) % 4;
  }
  return true;
}

HANDLE MailboxSwapChain::ConsumerAcquire() {
  std::lock_guard<std::mutex> lock(slots_mutex_);
  if (!has_completed_frame_.load(std::memory_order_acquire)) return nullptr;

  const int slot = latest_completed_slot_.load(std::memory_order_acquire);
  if (slot < 0) return nullptr;

  return slots_[slot].shared_handle;
}

void MailboxSwapChain::ConsumerHandleOpened(HANDLE handle) {
  if (!non_blocking_ || !handle) return;

  std::lock_guard<std::mutex> lock(slots_mutex_);
  uint64_t opened_submission = 0;
  for (const auto& slot : slots_) {
    if (slot.shared_handle == handle) {
      opened_submission = slot.submission_id;
      break;
    }
  }
  if (opened_submission == 0) return;

  // Flutter invokes the descriptor release callback after opening |handle|.
  // Opening this submission releases the previously bound EGL image. Keep two
  // opened generations between a retired slot and its reuse. This is still a
  // heuristic rather than a GPU-consumption fence, so the mode remains
  // experimental until Flutter exposes an actual consumer fence.
  for (auto& slot : slots_) {
    if (slot.state == SlotState::kRetired &&
        opened_submission >= slot.reuse_after_opened_submission) {
      slot.handle_opened = true;
    }
  }
}

void MailboxSwapChain::SetFrameAvailableCallback(
    std::function<void()> callback) {
  std::lock_guard<std::mutex> lock(callback_mutex_);
  frame_available_callback_ = std::move(callback);
}

HANDLE MailboxSwapChain::ReadHandleSnapshot() {
  std::lock_guard<std::mutex> lock(slots_mutex_);
  if (!has_completed_frame_.load(std::memory_order_acquire)) return nullptr;

  const int slot = latest_completed_slot_.load(std::memory_order_acquire);
  if (slot < 0) return nullptr;

  return slots_[slot].shared_handle;
}

HRESULT MailboxSwapChain::Resize(int32_t width, int32_t height) {
  if (non_blocking_) StopCompletionThread();

  HRESULT hr = S_OK;
  {
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
    hr = AllocateSlots();
  }

  if (non_blocking_ && SUCCEEDED(hr)) {
    try {
      StartCompletionThread();
    } catch (const std::system_error& error) {
      std::cout << "media_kit: MailboxSwapChain: failed to restart completion "
                   "thread after resize: "
                << error.what() << std::endl;
      return E_FAIL;
    }
  }
  return hr;
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
    WakeCompletionThread();
    return false;
  }

  const int submitted_slot = write_slot_;
  auto& write = slots_[submitted_slot];
  const HRESULT signal_hr =
      context4_->Signal(write.fence.Get(), ++write.fence_value);
  if (FAILED(signal_hr)) {
    write.state = SlotState::kFree;
    write_slot_ = -1;
    return false;
  }

  write.submission_id = ++next_submission_id_;
  write.state = SlotState::kPending;
  write_slot_ = -1;

  // Flush submits the fence but does not wait for it. Without this, a full
  // mailbox can stop issuing D3D work before the queued fences become visible.
  context4_->Flush();
  WakeCompletionThread();
  return false;
}

ID3D11Texture2D* MailboxSwapChain::RenderTargetNonBlocking() {
  if (write_slot_ >= 0) {
    return slots_[write_slot_].texture.Get();
  }

  PromoteCompletedFrames();
  for (auto& slot : slots_) {
    if (slot.state == SlotState::kRetired && slot.handle_opened) {
      slot.state = SlotState::kFree;
      slot.handle_opened = false;
    }
  }
  for (int slot = 0; slot < 4; ++slot) {
    if (slots_[slot].state == SlotState::kFree) {
      slots_[slot].state = SlotState::kWriting;
      write_slot_ = slot;
      return slots_[slot].texture.Get();
    }
  }

  return nullptr;
}

bool MailboxSwapChain::PromoteCompletedFrames() {
  int newest_completed = -1;
  uint64_t newest_submission = 0;

  for (int slot = 0; slot < 4; ++slot) {
    const auto& candidate = slots_[slot];
    if (candidate.state != SlotState::kPending || !candidate.fence ||
        !IsFenceComplete(candidate.fence.Get(), candidate.fence_value)) {
      continue;
    }
    if (newest_completed < 0 ||
        candidate.submission_id > newest_submission) {
      newest_completed = slot;
      newest_submission = candidate.submission_id;
    }
  }

  if (newest_completed < 0) return false;

  const int previously_published =
      latest_completed_slot_.load(std::memory_order_acquire);
  if (previously_published >= 0 && previously_published != newest_completed &&
      slots_[previously_published].state == SlotState::kPublished) {
    slots_[previously_published].state = SlotState::kRetired;
    slots_[previously_published].handle_opened = false;
    slots_[previously_published].reuse_after_opened_submission =
        slots_[previously_published].submission_id + 2;
  }

  for (int slot = 0; slot < 4; ++slot) {
    auto& candidate = slots_[slot];
    if (candidate.state == SlotState::kPending &&
        IsFenceComplete(candidate.fence.Get(), candidate.fence_value)) {
      candidate.state =
          slot == newest_completed ? SlotState::kPublished : SlotState::kFree;
    }
  }

  latest_completed_slot_.store(newest_completed, std::memory_order_release);
  has_completed_frame_.store(true, std::memory_order_release);
  published_frame_pending_ = true;
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
    slot.reuse_after_opened_submission = 0;
    slot.handle_opened = false;
    slot.state = SlotState::kFree;
  }
}

void MailboxSwapChain::StartCompletionThread() {
  {
    std::lock_guard<std::mutex> lock(completion_mutex_);
    completion_stop_ = false;
    completion_work_pending_ = false;
  }
  if (completion_stop_event_) {
    ::ResetEvent(completion_stop_event_);
  }
  completion_thread_ = std::thread([this]() { CompletionLoop(); });
}

void MailboxSwapChain::StopCompletionThread() {
  if (!completion_thread_.joinable()) return;

  {
    std::lock_guard<std::mutex> lock(completion_mutex_);
    completion_stop_ = true;
    completion_work_pending_ = true;
  }
  if (completion_stop_event_) {
    ::SetEvent(completion_stop_event_);
  }
  completion_cv_.notify_all();
  completion_thread_.join();
}

void MailboxSwapChain::WakeCompletionThread() {
  if (!non_blocking_) return;
  {
    std::lock_guard<std::mutex> lock(completion_mutex_);
    completion_work_pending_ = true;
  }
  completion_cv_.notify_one();
}

void MailboxSwapChain::CompletionLoop() {
  for (;;) {
    {
      std::unique_lock<std::mutex> lock(completion_mutex_);
      completion_cv_.wait(lock, [this]() {
        return completion_stop_ || completion_work_pending_;
      });
      if (completion_stop_) return;
      completion_work_pending_ = false;
    }

    for (;;) {
      Microsoft::WRL::ComPtr<ID3D11Fence> pending_fence;
      uint64_t pending_value = 0;
      uint64_t oldest_submission =
          (std::numeric_limits<uint64_t>::max)();
      bool frame_ready = false;

      {
        std::lock_guard<std::mutex> lock(slots_mutex_);
        PromoteCompletedFrames();
        frame_ready = TakePublishedFrame();

        for (const auto& slot : slots_) {
          if (slot.state == SlotState::kPending && slot.fence &&
              slot.submission_id < oldest_submission) {
            oldest_submission = slot.submission_id;
            pending_fence = slot.fence;
            pending_value = slot.fence_value;
          }
        }
      }

      if (frame_ready) {
        NotifyFrameAvailable();
      }
      if (!pending_fence) break;
      const uint64_t completed = pending_fence->GetCompletedValue();
      if (completed == kFenceDeviceRemovedValue) {
        const HRESULT removed_reason = device_->GetDeviceRemovedReason();
        std::cout << "media_kit: MailboxSwapChain: device removed while "
                     "waiting for a mailbox fence (hr=0x"
                  << std::hex << removed_reason << std::dec << ")"
                  << std::endl;
        break;
      }
      if (completed >= pending_value) continue;

      const HRESULT hr = pending_fence->SetEventOnCompletion(
          pending_value, fence_event_);
      if (FAILED(hr)) {
        std::cout << "media_kit: MailboxSwapChain: SetEventOnCompletion "
                     "failed (hr=0x"
                  << std::hex << hr << std::dec << ")" << std::endl;
        break;
      }

      HANDLE wait_handles[] = {completion_stop_event_, fence_event_};
      const DWORD wait =
          ::WaitForMultipleObjects(2, wait_handles, FALSE, INFINITE);
      if (wait == WAIT_OBJECT_0) return;
      if (wait != WAIT_OBJECT_0 + 1) {
        std::cout << "media_kit: MailboxSwapChain: fence wait failed (error="
                  << ::GetLastError() << ")" << std::endl;
        break;
      }
    }
  }
}

void MailboxSwapChain::NotifyFrameAvailable() {
  // Invoke under the same lock used by SetFrameAvailableCallback. Clearing
  // the callback during VideoOutput teardown then becomes a synchronization
  // barrier: no copied callback can outlive its VideoOutput owner.
  std::lock_guard<std::mutex> lock(callback_mutex_);
  if (frame_available_callback_) frame_available_callback_();
}

HRESULT MailboxSwapChain::WaitForSlot(int slot) {
  if (slot < 0 || slot >= 4) return E_INVALIDARG;

  auto& texture_slot = slots_[slot];
  if (!texture_slot.fence || texture_slot.fence_value == 0) return E_FAIL;
  if (IsFenceComplete(texture_slot.fence.Get(), texture_slot.fence_value)) {
    return S_OK;
  }

  HRESULT hr = texture_slot.fence->SetEventOnCompletion(
      texture_slot.fence_value, fence_event_);
  if (FAILED(hr)) return hr;

  constexpr DWORD kFenceWaitTimeoutMs = 2000;
  const ULONGLONG start = ::GetTickCount64();
  for (;;) {
    const uint64_t completed = texture_slot.fence->GetCompletedValue();
    if (completed == kFenceDeviceRemovedValue) {
      const HRESULT removed_reason = device_->GetDeviceRemovedReason();
      return FAILED(removed_reason) ? removed_reason : DXGI_ERROR_DEVICE_REMOVED;
    }
    if (completed >= texture_slot.fence_value) {
      return S_OK;
    }

    const ULONGLONG elapsed = ::GetTickCount64() - start;
    if (elapsed >= kFenceWaitTimeoutMs) break;

    const DWORD remaining =
        kFenceWaitTimeoutMs - static_cast<DWORD>(elapsed);
    const DWORD wait = ::WaitForSingleObject(fence_event_, remaining);
    if (wait == WAIT_OBJECT_0) {
      // A timed-out wait for an older slot can signal this shared event later.
      // Treat the event only as a wake-up and verify this slot's fence above.
      continue;
    }
    if (wait == WAIT_TIMEOUT) break;
    return HRESULT_FROM_WIN32(::GetLastError());
  }

  const HRESULT removed_reason = device_->GetDeviceRemovedReason();
  return FAILED(removed_reason) ? removed_reason
                                : HRESULT_FROM_WIN32(ERROR_TIMEOUT);
}

void MailboxSwapChain::ReleaseSlots() {
  for (auto& slot : slots_) {
    slot.texture.Reset();
    slot.shared_handle = nullptr;
    slot.fence.Reset();
    slot.fence_value = 0;
    slot.submission_id = 0;
    slot.reuse_after_opened_submission = 0;
    slot.handle_opened = false;
    slot.state = SlotState::kFree;
  }
}

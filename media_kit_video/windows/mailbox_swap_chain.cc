// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright (c) 2026 Predidit.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "mailbox_swap_chain.h"

#include <iostream>
#include <new>

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
                                  MailboxSwapChain** out) {
  if (!device || !out) return E_INVALIDARG;

  auto* p = new (std::nothrow) MailboxSwapChain();
  if (!p) return E_OUTOFMEMORY;

  p->device_ = device;
  p->width_ = width > 0 ? width : 1;
  p->height_ = height > 0 ? height : 1;
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
  std::lock_guard<std::mutex> lock(slots_mutex_);

  if (write_slot_ >= 0) {
    return slots_[write_slot_].texture.Get();
  }

  write_slot_ = next_write_slot_;
  return slots_[write_slot_].texture.Get();
}

bool MailboxSwapChain::ProducerCommit() {
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
  if (FAILED(hr)) return false;

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
  latest_completed_slot_.store(-1, std::memory_order_release);
  next_write_slot_ = 0;
  write_slot_ = -1;
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

HRESULT MailboxSwapChain::WaitForSlot(int slot) {
  if (slot < 0 || slot >= 4) return E_INVALIDARG;

  auto& texture_slot = slots_[slot];
  if (!texture_slot.fence || texture_slot.fence_value == 0) return E_FAIL;
  if (texture_slot.fence->GetCompletedValue() >= texture_slot.fence_value) {
    return S_OK;
  }

  HRESULT hr = texture_slot.fence->SetEventOnCompletion(
      texture_slot.fence_value, fence_event_);
  if (FAILED(hr)) return hr;

  const DWORD wait = ::WaitForSingleObject(fence_event_, INFINITE);
  return wait == WAIT_OBJECT_0 ? S_OK : HRESULT_FROM_WIN32(::GetLastError());
}

void MailboxSwapChain::ReleaseSlots() {
  for (auto& slot : slots_) {
    slot.texture.Reset();
    slot.shared_handle = nullptr;
    slot.fence.Reset();
    slot.fence_value = 0;
  }
}

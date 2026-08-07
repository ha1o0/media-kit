// This file is a part of media_kit.

#include "fixed_handle_texture_bridge.h"

#include <iostream>
#include <new>

FixedHandleTextureBridge::~FixedHandleTextureBridge() {
  ReleaseTextures();
}

HRESULT FixedHandleTextureBridge::Create(ID3D11Device* device,
                                         int32_t width,
                                         int32_t height,
                                         FixedHandleTextureBridge** out) {
  if (!device || !out) return E_INVALIDARG;

  auto* bridge = new (std::nothrow) FixedHandleTextureBridge();
  if (!bridge) return E_OUTOFMEMORY;

  bridge->device_ = device;
  bridge->width_ = width > 0 ? width : 1;
  bridge->height_ = height > 0 ? height : 1;
  device->GetImmediateContext(bridge->context_.GetAddressOf());
  if (!bridge->context_) {
    delete bridge;
    return E_FAIL;
  }

  const HRESULT hr = bridge->AllocateTextures();
  if (FAILED(hr)) {
    delete bridge;
    return hr;
  }

  *out = bridge;
  return S_OK;
}

bool FixedHandleTextureBridge::ProducerCommit() {
  if (!context_ || !render_texture_ || !shared_texture_) return false;

  // Both operations remain on the GPU. Flush makes the copy visible to the
  // Flutter device which imports the stable shared HANDLE.
  context_->CopyResource(shared_texture_.Get(), render_texture_.Get());
  context_->Flush();
  return true;
}

HRESULT FixedHandleTextureBridge::Resize(int32_t width, int32_t height) {
  if (width == width_ && height == height_ && render_texture_ &&
      shared_texture_) {
    return S_OK;
  }

  ReleaseTextures();
  width_ = width > 0 ? width : 1;
  height_ = height > 0 ? height : 1;
  return AllocateTextures();
}

HRESULT FixedHandleTextureBridge::AllocateTextures() {
  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = static_cast<UINT>(width_);
  desc.Height = static_cast<UINT>(height_);
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;

  HRESULT hr = device_->CreateTexture2D(&desc, nullptr, &render_texture_);
  if (FAILED(hr)) {
    std::cout << "media_kit: FixedHandleTextureBridge: failed to create "
                 "render texture (hr=0x"
              << std::hex << hr << std::dec << ")" << std::endl;
    return hr;
  }

  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
  hr = device_->CreateTexture2D(&desc, nullptr, &shared_texture_);
  if (FAILED(hr)) {
    std::cout << "media_kit: FixedHandleTextureBridge: failed to create "
                 "shared texture (hr=0x"
              << std::hex << hr << std::dec << ")" << std::endl;
    return hr;
  }

  Microsoft::WRL::ComPtr<IDXGIResource> resource;
  hr = shared_texture_.As(&resource);
  if (FAILED(hr)) return hr;

  HANDLE handle = nullptr;
  hr = resource->GetSharedHandle(&handle);
  if (FAILED(hr)) return hr;
  shared_handle_.store(handle, std::memory_order_release);

  Microsoft::WRL::ComPtr<ID3D11RenderTargetView> view;
  if (SUCCEEDED(device_->CreateRenderTargetView(shared_texture_.Get(), nullptr,
                                                 &view))) {
    constexpr float clear_color[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    context_->ClearRenderTargetView(view.Get(), clear_color);
    context_->Flush();
  }

  return S_OK;
}

void FixedHandleTextureBridge::ReleaseTextures() {
  shared_handle_.store(nullptr, std::memory_order_release);
  shared_texture_.Reset();
  render_texture_.Reset();
}

// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright (c) 2026 Predidit.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#ifndef D3D11_RENDERER_H_
#define D3D11_RENDERER_H_

#include <Windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <dxgi1_2.h>
#include <wrl.h>

#include <cstdint>
#include <memory>

#include "d3d11_anime4k_processor.h"
#include "mailbox_swap_chain.h"

class D3D11Renderer {
 public:
  int32_t width() const { return width_; }
  int32_t height() const { return height_; }

  ID3D11Device* device() const { return d3d_11_device_.Get(); }
  ID3D11Texture2D* render_target();

  explicit D3D11Renderer(int32_t width,
                         int32_t height,
                         IDXGIAdapter* flutter_adapter = nullptr);
  ~D3D11Renderer();

  void SetSize(int32_t width, int32_t height);
  void SetAnime4KEnabled(bool enabled);
  bool ProducerCommit();
  HANDLE ConsumerAcquire();
  HANDLE ReadHandleSnapshot() const;

 private:
  bool CreateD3D11Device(IDXGIAdapter* flutter_adapter);
  bool CreateMailbox();

  int32_t width_ = 1;
  int32_t height_ = 1;

  Microsoft::WRL::ComPtr<ID3D11Device> d3d_11_device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> d3d_11_device_context_;
  Microsoft::WRL::ComPtr<MailboxSwapChain> mailbox_swap_chain_;
  std::unique_ptr<D3D11Anime4KProcessor> anime4k_processor_;
  bool anime4k_enabled_ = false;
  bool anime4k_frame_pending_ = false;
};

#endif  // D3D11_RENDERER_H_

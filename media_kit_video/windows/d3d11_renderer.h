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
#include <d3dcompiler.h>
#include <dxgi.h>
#include <dxgi1_2.h>
#include <wrl.h>

#include <cstdint>

#include "mailbox_swap_chain.h"

class D3D11Renderer {
 public:
  int32_t width() const { return width_; }
  int32_t height() const { return height_; }

  ID3D11Device* device() const { return d3d_11_device_.Get(); }
  ID3D11Texture2D* render_target() const {
    return texture_sdr_compensation_enabled_ && mpv_render_target_
               ? mpv_render_target_.Get()
               : (mailbox_swap_chain_ ? mailbox_swap_chain_->RenderTarget()
                                       : nullptr);
  }

  explicit D3D11Renderer(int32_t width,
                         int32_t height,
                         IDXGIAdapter* flutter_adapter = nullptr);
  ~D3D11Renderer();

  void SetSize(int32_t width, int32_t height);
  void SetTextureSdrCompensationEnabled(bool enabled);
  bool ProducerCommit();
  HANDLE ConsumerAcquire();
  HANDLE ReadHandleSnapshot() const;

 private:
  bool CreateD3D11Device(IDXGIAdapter* flutter_adapter);
  bool CreateMailbox();
  bool EnsureTextureSdrCompensationResources();
  bool ApplyTextureSdrCompensation(ID3D11Texture2D* output_texture);
  void ReleaseTextureSdrCompensationResources();

  int32_t width_ = 1;
  int32_t height_ = 1;
  bool texture_sdr_compensation_enabled_ = false;
  int32_t texture_sdr_compensation_log_count_ = 0;

  Microsoft::WRL::ComPtr<ID3D11Device> d3d_11_device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> d3d_11_device_context_;
  Microsoft::WRL::ComPtr<MailboxSwapChain> mailbox_swap_chain_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> mpv_render_target_;
  Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> mpv_render_target_srv_;
  Microsoft::WRL::ComPtr<ID3D11VertexShader> texture_sdr_vertex_shader_;
  Microsoft::WRL::ComPtr<ID3D11PixelShader> texture_sdr_pixel_shader_;
  Microsoft::WRL::ComPtr<ID3D11SamplerState> texture_sdr_sampler_state_;
};

#endif  // D3D11_RENDERER_H_

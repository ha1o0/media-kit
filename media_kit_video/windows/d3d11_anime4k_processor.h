// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright (c) 2026 Predidit.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#ifndef D3D11_ANIME4K_PROCESSOR_H_
#define D3D11_ANIME4K_PROCESSOR_H_

#include <d3d11.h>
#include <wrl.h>

#include <array>
#include <cstdint>

class D3D11Anime4KProcessor {
 public:
  D3D11Anime4KProcessor(ID3D11Device* device, ID3D11DeviceContext* context);
  ~D3D11Anime4KProcessor();

  ID3D11Texture2D* input_texture() const { return input_texture_.Get(); }

  bool EnsureSize(int32_t width, int32_t height);
  bool Process(ID3D11Texture2D* output_texture);
  void Reset();

 private:
  struct PassTexture {
    Microsoft::WRL::ComPtr<ID3D11Texture2D> texture;
    Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> srv;
    Microsoft::WRL::ComPtr<ID3D11RenderTargetView> rtv;
  };

  bool EnsureShaders();
  bool CreateIntermediateTexture(int32_t width, int32_t height);
  bool RenderPass(ID3D11PixelShader* shader,
                  ID3D11RenderTargetView* output_rtv,
                  ID3D11ShaderResourceView* const* srvs,
                  UINT srv_count);

  int32_t width_ = 0;
  int32_t height_ = 0;

  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> input_texture_;
  Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> input_srv_;
  std::array<PassTexture, 3> restore_textures_;
  Microsoft::WRL::ComPtr<ID3D11VertexShader> vertex_shader_;
  std::array<Microsoft::WRL::ComPtr<ID3D11PixelShader>, 4> pixel_shaders_;
  Microsoft::WRL::ComPtr<ID3D11SamplerState> sampler_;
};

#endif  // D3D11_ANIME4K_PROCESSOR_H_

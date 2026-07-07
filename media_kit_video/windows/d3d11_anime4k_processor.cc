// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright (c) 2026 Predidit.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "d3d11_anime4k_processor.h"

#include <d3dcompiler.h>

#include <cstring>
#include <iostream>

#include "d3d11_anime4k_restore_s_shaders.h"

#pragma comment(lib, "d3dcompiler.lib")

namespace {

const char kVertexShader[] = R"(
struct VSOut {
  float4 position : SV_POSITION;
  float2 uv : TEXCOORD0;
};

VSOut main(uint vertex_id : SV_VertexID) {
  float2 positions[3] = {
    float2(-1.0, -1.0),
    float2(-1.0,  3.0),
    float2( 3.0, -1.0),
  };
  float2 uvs[3] = {
    float2(0.0, 1.0),
    float2(0.0, -1.0),
    float2(2.0, 1.0),
  };

  VSOut output;
  output.position = float4(positions[vertex_id], 0.0, 1.0);
  output.uv = uvs[vertex_id];
  return output;
}
)";


bool CompileShader(const char* source,
                   const char* entry_point,
                   const char* target,
                   ID3DBlob** blob) {
  Microsoft::WRL::ComPtr<ID3DBlob> error_blob;
  const UINT flags =
#if defined(_DEBUG)
      D3DCOMPILE_DEBUG | D3DCOMPILE_SKIP_OPTIMIZATION;
#else
      D3DCOMPILE_OPTIMIZATION_LEVEL3;
#endif

  const HRESULT hr =
      D3DCompile(source, strlen(source), nullptr, nullptr, nullptr, entry_point,
                 target, flags, 0, blob, error_blob.GetAddressOf());
  if (FAILED(hr)) {
    std::cout << "media_kit: D3D11Anime4KProcessor: shader compile failed "
                 "(hr=0x"
              << std::hex << hr << std::dec << ")";
    if (error_blob) {
      std::cout << ": "
                << static_cast<const char*>(error_blob->GetBufferPointer());
    }
    std::cout << std::endl;
    return false;
  }
  return true;
}

}  // namespace

D3D11Anime4KProcessor::D3D11Anime4KProcessor(ID3D11Device* device,
                                             ID3D11DeviceContext* context)
    : device_(device), context_(context) {}

D3D11Anime4KProcessor::~D3D11Anime4KProcessor() {
  Reset();
}

bool D3D11Anime4KProcessor::EnsureSize(int32_t width, int32_t height) {
  width = width > 0 ? width : 1;
  height = height > 0 ? height : 1;

  if (!EnsureShaders()) {
    return false;
  }

  auto restore_ready = true;
  for (const auto& texture : restore_textures_) {
    restore_ready =
        restore_ready && texture.texture && texture.srv && texture.rtv;
  }
  if (input_texture_ && input_srv_ && restore_ready && width_ == width &&
      height_ == height) {
    return true;
  }

  return CreateIntermediateTexture(width, height);
}

bool D3D11Anime4KProcessor::Process(ID3D11Texture2D* output_texture) {
  if (!output_texture || !input_srv_ || !vertex_shader_ || !sampler_) {
    return false;
  }
  for (const auto& shader : pixel_shaders_) {
    if (!shader) {
      return false;
    }
  }
  for (const auto& texture : restore_textures_) {
    if (!texture.texture || !texture.srv || !texture.rtv) {
      return false;
    }
  }

  ID3D11ShaderResourceView* pass0_srvs[] = {input_srv_.Get()};
  if (!RenderPass(pixel_shaders_[0].Get(), restore_textures_[0].rtv.Get(),
                  pass0_srvs, 1)) {
    return false;
  }

  ID3D11ShaderResourceView* pass1_srvs[] = {restore_textures_[0].srv.Get()};
  if (!RenderPass(pixel_shaders_[1].Get(), restore_textures_[1].rtv.Get(),
                  pass1_srvs, 1)) {
    return false;
  }

  ID3D11ShaderResourceView* pass2_srvs[] = {restore_textures_[1].srv.Get()};
  if (!RenderPass(pixel_shaders_[2].Get(), restore_textures_[2].rtv.Get(),
                  pass2_srvs, 1)) {
    return false;
  }

  Microsoft::WRL::ComPtr<ID3D11RenderTargetView> output_rtv;
  HRESULT hr = device_->CreateRenderTargetView(output_texture, nullptr,
                                               output_rtv.GetAddressOf());
  if (FAILED(hr)) {
    std::cout
        << "media_kit: D3D11Anime4KProcessor: output RTV creation failed "
           "(hr=0x"
        << std::hex << hr << std::dec << ")" << std::endl;
    return false;
  }

  ID3D11ShaderResourceView* final_srvs[] = {input_srv_.Get(),
                                            restore_textures_[2].srv.Get()};
  return RenderPass(pixel_shaders_[3].Get(), output_rtv.Get(), final_srvs, 2);
}

bool D3D11Anime4KProcessor::RenderPass(
    ID3D11PixelShader* shader,
    ID3D11RenderTargetView* output_rtv,
    ID3D11ShaderResourceView* const* srvs,
    UINT srv_count) {
  if (!shader || !output_rtv || !srvs || srv_count == 0) {
    return false;
  }

  D3D11_VIEWPORT viewport = {};
  viewport.Width = static_cast<float>(width_);
  viewport.Height = static_cast<float>(height_);
  viewport.MinDepth = 0.0f;
  viewport.MaxDepth = 1.0f;

  ID3D11RenderTargetView* rtvs[] = {output_rtv};
  ID3D11SamplerState* samplers[] = {sampler_.Get()};

  const float blend_factor[4] = {0.0f, 0.0f, 0.0f, 0.0f};
  context_->OMSetRenderTargets(1, rtvs, nullptr);
  context_->OMSetBlendState(nullptr, blend_factor, 0xffffffff);
  context_->OMSetDepthStencilState(nullptr, 0);
  context_->RSSetState(nullptr);
  context_->RSSetViewports(1, &viewport);
  context_->IASetInputLayout(nullptr);
  context_->IASetVertexBuffers(0, 0, nullptr, nullptr, nullptr);
  context_->IASetIndexBuffer(nullptr, DXGI_FORMAT_UNKNOWN, 0);
  context_->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  context_->VSSetShader(vertex_shader_.Get(), nullptr, 0);
  context_->PSSetShader(shader, nullptr, 0);
  context_->PSSetShaderResources(0, srv_count, srvs);
  context_->PSSetSamplers(0, 1, samplers);
  context_->Draw(3, 0);

  ID3D11ShaderResourceView* null_srvs[] = {nullptr, nullptr};
  ID3D11SamplerState* null_samplers[] = {nullptr};
  ID3D11RenderTargetView* null_rtvs[] = {nullptr};
  context_->PSSetShaderResources(0, 2, null_srvs);
  context_->PSSetSamplers(0, 1, null_samplers);
  context_->OMSetRenderTargets(1, null_rtvs, nullptr);
  context_->VSSetShader(nullptr, nullptr, 0);
  context_->PSSetShader(nullptr, nullptr, 0);

  return true;
}

void D3D11Anime4KProcessor::Reset() {
  sampler_.Reset();
  for (auto& shader : pixel_shaders_) {
    shader.Reset();
  }
  vertex_shader_.Reset();
  for (auto& texture : restore_textures_) {
    texture.rtv.Reset();
    texture.srv.Reset();
    texture.texture.Reset();
  }
  input_srv_.Reset();
  input_texture_.Reset();
  width_ = 0;
  height_ = 0;
}

bool D3D11Anime4KProcessor::EnsureShaders() {
  auto pixel_shaders_ready = true;
  for (const auto& shader : pixel_shaders_) {
    pixel_shaders_ready = pixel_shaders_ready && shader;
  }
  if (vertex_shader_ && pixel_shaders_ready && sampler_) {
    return true;
  }

  Microsoft::WRL::ComPtr<ID3DBlob> vs_blob;
  if (!CompileShader(kVertexShader, "main", "vs_4_0", vs_blob.GetAddressOf())) {
    return false;
  }

  HRESULT hr = device_->CreateVertexShader(
      vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nullptr,
      vertex_shader_.GetAddressOf());
  if (FAILED(hr)) {
    std::cout
        << "media_kit: D3D11Anime4KProcessor: vertex shader creation failed "
           "(hr=0x"
        << std::hex << hr << std::dec << ")" << std::endl;
    return false;
  }

  for (size_t i = 0; i < pixel_shaders_.size(); ++i) {
    Microsoft::WRL::ComPtr<ID3DBlob> ps_blob;
    if (!CompileShader(anime4k_restore_s::kPassShaders[i], "main", "ps_4_0",
                       ps_blob.GetAddressOf())) {
      return false;
    }

    hr = device_->CreatePixelShader(ps_blob->GetBufferPointer(),
                                    ps_blob->GetBufferSize(), nullptr,
                                    pixel_shaders_[i].GetAddressOf());
    if (FAILED(hr)) {
      std::cout
          << "media_kit: D3D11Anime4KProcessor: pixel shader " << i
          << " creation failed (hr=0x" << std::hex << hr << std::dec << ")"
          << std::endl;
      return false;
    }
  }

  D3D11_SAMPLER_DESC sampler_desc = {};
  sampler_desc.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
  sampler_desc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler_desc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler_desc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler_desc.MinLOD = 0;
  sampler_desc.MaxLOD = D3D11_FLOAT32_MAX;

  hr = device_->CreateSamplerState(&sampler_desc, sampler_.GetAddressOf());
  if (FAILED(hr)) {
    std::cout
        << "media_kit: D3D11Anime4KProcessor: sampler creation failed (hr=0x"
        << std::hex << hr << std::dec << ")" << std::endl;
    return false;
  }

  return true;
}

bool D3D11Anime4KProcessor::CreateIntermediateTexture(int32_t width,
                                                      int32_t height) {
  input_srv_.Reset();
  input_texture_.Reset();
  for (auto& texture : restore_textures_) {
    texture.rtv.Reset();
    texture.srv.Reset();
    texture.texture.Reset();
  }

  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = static_cast<UINT>(width);
  desc.Height = static_cast<UINT>(height);
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.SampleDesc.Quality = 0;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;

  HRESULT hr =
      device_->CreateTexture2D(&desc, nullptr, input_texture_.GetAddressOf());
  if (FAILED(hr)) {
    std::cout
        << "media_kit: D3D11Anime4KProcessor: input texture creation failed "
           "(hr=0x"
        << std::hex << hr << std::dec << ")" << std::endl;
    return false;
  }

  hr = device_->CreateShaderResourceView(input_texture_.Get(), nullptr,
                                         input_srv_.GetAddressOf());
  if (FAILED(hr)) {
    std::cout << "media_kit: D3D11Anime4KProcessor: input SRV creation failed "
                 "(hr=0x"
              << std::hex << hr << std::dec << ")" << std::endl;
    input_texture_.Reset();
    return false;
  }

  D3D11_TEXTURE2D_DESC restore_desc = desc;
  restore_desc.Format = DXGI_FORMAT_R16G16B16A16_FLOAT;

  for (size_t i = 0; i < restore_textures_.size(); ++i) {
    auto& texture = restore_textures_[i];
    hr = device_->CreateTexture2D(&restore_desc, nullptr,
                                  texture.texture.GetAddressOf());
    if (FAILED(hr)) {
      std::cout << "media_kit: D3D11Anime4KProcessor: restore texture " << i
                << " creation failed (hr=0x" << std::hex << hr << std::dec
                << ")" << std::endl;
      return false;
    }

    hr = device_->CreateShaderResourceView(texture.texture.Get(), nullptr,
                                           texture.srv.GetAddressOf());
    if (FAILED(hr)) {
      std::cout << "media_kit: D3D11Anime4KProcessor: restore SRV " << i
                << " creation failed (hr=0x" << std::hex << hr << std::dec
                << ")" << std::endl;
      return false;
    }

    hr = device_->CreateRenderTargetView(texture.texture.Get(), nullptr,
                                         texture.rtv.GetAddressOf());
    if (FAILED(hr)) {
      std::cout << "media_kit: D3D11Anime4KProcessor: restore RTV " << i
                << " creation failed (hr=0x" << std::hex << hr << std::dec
                << ")" << std::endl;
      return false;
    }
  }

  width_ = width;
  height_ = height;
  return true;
}

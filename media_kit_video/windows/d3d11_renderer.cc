// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright (c) 2026 Predidit.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "d3d11_renderer.h"

#include <iostream>
#include <iterator>
#include <stdexcept>
#include <cstring>

#include "utils.h"

#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "d3dcompiler.lib")

namespace {

constexpr char kHdrToneMappingShader[] = R"(
struct VSOut {
  float4 pos : SV_POSITION;
  float2 uv : TEXCOORD0;
};

VSOut VSMain(uint vertex_id : SV_VertexID) {
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
  output.pos = float4(positions[vertex_id], 0.0, 1.0);
  output.uv = uvs[vertex_id];
  return output;
}

Texture2D source_texture : register(t0);
SamplerState source_sampler : register(s0);

float4 PSMain(VSOut input) : SV_TARGET {
  float4 color = source_texture.Sample(source_sampler, input.uv);
  float3 rgb = saturate(color.rgb);
  float y = max(dot(rgb, float3(0.2126, 0.7152, 0.0722)), 0.00001);
  float lifted_y = pow(y, 0.82);
  float shadow_gate = smoothstep(0.015, 0.08, y);
  float highlight_gate = 1.0 - smoothstep(0.38, 0.78, y);
  float lift_amount = 0.52 * shadow_gate * highlight_gate;
  float target_y = lerp(y, lifted_y, lift_amount);
  float gain = min(target_y / y, 1.42);
  float max_channel = max(rgb.r, max(rgb.g, rgb.b));
  if (max_channel > 0.00001) {
    gain = min(gain, 0.985 / max_channel);
  }
  float3 lifted_rgb = rgb * gain;
  float lifted_luma = dot(lifted_rgb, float3(0.2126, 0.7152, 0.0722));
  float saturation = lerp(1.0, 0.94, smoothstep(1.06, 1.32, gain));
  lifted_rgb = lifted_luma + (lifted_rgb - lifted_luma) * saturation;
  float red_excess = lifted_rgb.r - max(lifted_rgb.g, lifted_rgb.b);
  float red_balance = smoothstep(0.015, 0.16, red_excess) *
                      smoothstep(1.02, 1.28, gain);
  lifted_rgb.r *= 1.0 - 0.035 * red_balance;
  return float4(saturate(lifted_rgb), color.a);
}
)";

bool CompileShader(const char* entry_point,
                   const char* target,
                   ID3DBlob** blob) {
  Microsoft::WRL::ComPtr<ID3DBlob> errors;
  const HRESULT hr = D3DCompile(
      kHdrToneMappingShader, strlen(kHdrToneMappingShader), nullptr, nullptr,
      nullptr, entry_point, target, D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, blob,
      errors.GetAddressOf());
  if (FAILED(hr)) {
    std::cout << "media_kit: D3D11Renderer: HDR shader compile failed ("
              << entry_point << ", hr=0x" << std::hex << hr << std::dec
              << ")";
    if (errors) {
      std::cout << ": "
                << static_cast<const char*>(errors->GetBufferPointer());
    }
    std::cout << std::endl;
    return false;
  }
  return true;
}

}  // namespace

D3D11Renderer::D3D11Renderer(int32_t width,
                             int32_t height,
                             IDXGIAdapter* flutter_adapter)
    : width_(width), height_(height) {
  if (!CreateD3D11Device(flutter_adapter)) {
    throw std::runtime_error("Unable to create Direct3D 11 device.");
  }
  if (!CreateMailbox()) {
    throw std::runtime_error("Unable to create mailbox textures.");
  }
}

D3D11Renderer::~D3D11Renderer() {
  ReleaseHdrToneMappingResources();
  mailbox_swap_chain_.Reset();
  d3d_11_device_context_.Reset();
  d3d_11_device_.Reset();
}

void D3D11Renderer::SetSize(int32_t width, int32_t height) {
  if (width == width_ && height == height_) return;
  width_ = width;
  height_ = height;
  if (mailbox_swap_chain_) {
    const HRESULT hr = mailbox_swap_chain_->Resize(width_, height_);
    if (FAILED(hr)) {
      std::cout << "media_kit: D3D11Renderer: mailbox resize failed (hr=0x"
                << std::hex << hr << std::dec << ")" << std::endl;
    }
  }
  ReleaseHdrToneMappingResources();
}

void D3D11Renderer::SetHdrToneMappingEnabled(bool enabled) {
  if (hdr_tone_mapping_enabled_ == enabled) return;
  hdr_tone_mapping_enabled_ = enabled;
  if (enabled) {
    if (!EnsureHdrToneMappingResources()) {
      hdr_tone_mapping_enabled_ = false;
      ReleaseHdrToneMappingResources();
      std::cout << "media_kit: D3D11Renderer: Native HDR tone mapping "
                   "failed to initialize; using direct output."
                << std::endl;
      return;
    }
    std::cout << "media_kit: D3D11Renderer: Native HDR tone mapping enabled."
              << std::endl;
  } else {
    ReleaseHdrToneMappingResources();
    std::cout << "media_kit: D3D11Renderer: Native HDR tone mapping disabled."
              << std::endl;
  }
}

bool D3D11Renderer::ProducerCommit() {
  if (mailbox_swap_chain_) {
    if (hdr_tone_mapping_enabled_) {
      ID3D11Texture2D* output = mailbox_swap_chain_->RenderTarget();
      if (!ApplyHdrToneMapping(output)) {
        return false;
      }
    }
    return mailbox_swap_chain_->ProducerCommit();
  }
  return false;
}

HANDLE D3D11Renderer::ConsumerAcquire() {
  return mailbox_swap_chain_ ? mailbox_swap_chain_->ConsumerAcquire() : nullptr;
}

HANDLE D3D11Renderer::ReadHandleSnapshot() const {
  return mailbox_swap_chain_ ? mailbox_swap_chain_->ReadHandleSnapshot()
                             : nullptr;
}

bool D3D11Renderer::CreateD3D11Device(IDXGIAdapter* flutter_adapter) {
  if (d3d_11_device_) return true;

  const D3D_FEATURE_LEVEL feature_levels[] = {
      D3D_FEATURE_LEVEL_11_1,
      D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0,
      D3D_FEATURE_LEVEL_9_3,
  };

  Microsoft::WRL::ComPtr<IDXGIAdapter> adapter(flutter_adapter);
  D3D_DRIVER_TYPE driver_type = D3D_DRIVER_TYPE_UNKNOWN;

  if (!adapter) {
    if (Utils::IsWindows10RTMOrGreater()) {
      driver_type = D3D_DRIVER_TYPE_HARDWARE;
    } else {
      Microsoft::WRL::ComPtr<IDXGIFactory> dxgi;
      ::CreateDXGIFactory(IID_PPV_ARGS(dxgi.GetAddressOf()));
      if (dxgi) {
        dxgi->EnumAdapters(0, &adapter);
      }
    }
  } else {
    std::cout << "media_kit: D3D11Renderer: Using Flutter's DXGI adapter."
              << std::endl;
  }

  const HRESULT hr = ::D3D11CreateDevice(
      adapter.Get(), driver_type, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
      feature_levels, static_cast<UINT>(std::size(feature_levels)),
      D3D11_SDK_VERSION, d3d_11_device_.GetAddressOf(), nullptr,
      d3d_11_device_context_.GetAddressOf());

  if (FAILED(hr)) {
    std::cout << "media_kit: D3D11Renderer: D3D11CreateDevice failed (hr=0x"
              << std::hex << hr << std::dec << ")" << std::endl;
    return false;
  }

  Microsoft::WRL::ComPtr<IDXGIDevice> dxgi_device;
  if (SUCCEEDED(d3d_11_device_.As(&dxgi_device)) && dxgi_device) {
    dxgi_device->SetGPUThreadPriority(5);
  }

  return true;
}

bool D3D11Renderer::CreateMailbox() {
  MailboxSwapChain* raw = nullptr;
  const HRESULT hr =
      MailboxSwapChain::Create(d3d_11_device_.Get(), width_, height_, &raw);
  if (FAILED(hr)) {
    std::cout << "media_kit: D3D11Renderer: MailboxSwapChain::Create failed "
                 "(hr=0x"
              << std::hex << hr << std::dec << ")" << std::endl;
    return false;
  }
  mailbox_swap_chain_.Attach(raw);
  return true;
}

bool D3D11Renderer::EnsureHdrToneMappingResources() {
  if (!d3d_11_device_ || width_ <= 0 || height_ <= 0) return false;

  if (!mpv_render_target_) {
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
    desc.MiscFlags = 0;

    HRESULT hr = d3d_11_device_->CreateTexture2D(
        &desc, nullptr, mpv_render_target_.GetAddressOf());
    if (FAILED(hr)) {
      std::cout << "media_kit: D3D11Renderer: HDR texture create failed "
                   "(hr=0x"
                << std::hex << hr << std::dec << ")" << std::endl;
      return false;
    }

    hr = d3d_11_device_->CreateShaderResourceView(
        mpv_render_target_.Get(), nullptr,
        mpv_render_target_srv_.GetAddressOf());
    if (FAILED(hr)) {
      std::cout << "media_kit: D3D11Renderer: HDR SRV create failed (hr=0x"
                << std::hex << hr << std::dec << ")" << std::endl;
      ReleaseHdrToneMappingResources();
      return false;
    }
  }

  if (!hdr_vertex_shader_ || !hdr_pixel_shader_) {
    Microsoft::WRL::ComPtr<ID3DBlob> vs_blob;
    Microsoft::WRL::ComPtr<ID3DBlob> ps_blob;
    if (!CompileShader("VSMain", "vs_4_0", vs_blob.GetAddressOf()) ||
        !CompileShader("PSMain", "ps_4_0", ps_blob.GetAddressOf())) {
      return false;
    }

    HRESULT hr = d3d_11_device_->CreateVertexShader(
        vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nullptr,
        hdr_vertex_shader_.GetAddressOf());
    if (FAILED(hr)) {
      std::cout << "media_kit: D3D11Renderer: HDR vertex shader create failed "
                   "(hr=0x"
                << std::hex << hr << std::dec << ")" << std::endl;
      return false;
    }

    hr = d3d_11_device_->CreatePixelShader(
        ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nullptr,
        hdr_pixel_shader_.GetAddressOf());
    if (FAILED(hr)) {
      std::cout << "media_kit: D3D11Renderer: HDR pixel shader create failed "
                   "(hr=0x"
                << std::hex << hr << std::dec << ")" << std::endl;
      return false;
    }
  }

  if (!hdr_sampler_state_) {
    D3D11_SAMPLER_DESC desc = {};
    desc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    desc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
    desc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
    desc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    desc.ComparisonFunc = D3D11_COMPARISON_NEVER;
    desc.MinLOD = 0;
    desc.MaxLOD = D3D11_FLOAT32_MAX;
    const HRESULT hr = d3d_11_device_->CreateSamplerState(
        &desc, hdr_sampler_state_.GetAddressOf());
    if (FAILED(hr)) {
      std::cout << "media_kit: D3D11Renderer: HDR sampler create failed "
                   "(hr=0x"
                << std::hex << hr << std::dec << ")" << std::endl;
      return false;
    }
  }

  return true;
}

bool D3D11Renderer::ApplyHdrToneMapping(ID3D11Texture2D* output_texture) {
  if (!output_texture || !EnsureHdrToneMappingResources()) return false;

  Microsoft::WRL::ComPtr<ID3D11RenderTargetView> output_rtv;
  HRESULT hr = d3d_11_device_->CreateRenderTargetView(
      output_texture, nullptr, output_rtv.GetAddressOf());
  if (FAILED(hr)) {
    std::cout << "media_kit: D3D11Renderer: HDR RTV create failed (hr=0x"
              << std::hex << hr << std::dec << ")" << std::endl;
    return false;
  }

  ID3D11RenderTargetView* rtvs[] = {output_rtv.Get()};
  d3d_11_device_context_->OMSetRenderTargets(1, rtvs, nullptr);

  D3D11_VIEWPORT viewport = {};
  viewport.TopLeftX = 0.0f;
  viewport.TopLeftY = 0.0f;
  viewport.Width = static_cast<float>(width_);
  viewport.Height = static_cast<float>(height_);
  viewport.MinDepth = 0.0f;
  viewport.MaxDepth = 1.0f;
  d3d_11_device_context_->RSSetViewports(1, &viewport);

  ID3D11ShaderResourceView* srvs[] = {mpv_render_target_srv_.Get()};
  ID3D11SamplerState* samplers[] = {hdr_sampler_state_.Get()};
  d3d_11_device_context_->IASetInputLayout(nullptr);
  d3d_11_device_context_->IASetPrimitiveTopology(
      D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  d3d_11_device_context_->VSSetShader(hdr_vertex_shader_.Get(), nullptr, 0);
  d3d_11_device_context_->PSSetShader(hdr_pixel_shader_.Get(), nullptr, 0);
  d3d_11_device_context_->PSSetShaderResources(0, 1, srvs);
  d3d_11_device_context_->PSSetSamplers(0, 1, samplers);
  d3d_11_device_context_->Draw(3, 0);

  ID3D11ShaderResourceView* null_srvs[] = {nullptr};
  ID3D11SamplerState* null_samplers[] = {nullptr};
  ID3D11RenderTargetView* null_rtvs[] = {nullptr};
  d3d_11_device_context_->PSSetShaderResources(0, 1, null_srvs);
  d3d_11_device_context_->PSSetSamplers(0, 1, null_samplers);
  d3d_11_device_context_->OMSetRenderTargets(1, null_rtvs, nullptr);
  return true;
}

void D3D11Renderer::ReleaseHdrToneMappingResources() {
  mpv_render_target_srv_.Reset();
  mpv_render_target_.Reset();
}

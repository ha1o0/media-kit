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
#include <string>
#include <chrono>

#include "utils.h"
#include "gpu_thread_priority.h"
#include "performance_metrics.h"

#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3d11.lib")

D3D11Renderer::D3D11Renderer(int32_t width,
                             int32_t height,
                             IDXGIAdapter* flutter_adapter,
                             media_kit_video::VideoOutputMode output_mode)
    : width_(width), height_(height), output_mode_(output_mode) {
  if (!CreateD3D11Device(flutter_adapter)) {
    throw std::runtime_error("Unable to create Direct3D 11 device.");
  }
  if (!CreateFrameBridge()) {
    throw std::runtime_error("Unable to create D3D11 frame bridge.");
  }
}

D3D11Renderer::~D3D11Renderer() {
  anime4k_processor_.reset(nullptr);
  fixed_handle_bridge_.reset(nullptr);
  mailbox_swap_chain_.Reset();
  d3d_11_device_context_.Reset();
  d3d_11_device_.Reset();
}

ID3D11Texture2D* D3D11Renderer::render_target() {
  anime4k_frame_pending_ = false;
  if (!mailbox_swap_chain_ && !fixed_handle_bridge_) {
    return nullptr;
  }

  ID3D11Texture2D* frame_target = FrameRenderTarget();
  if (!frame_target) return nullptr;

  if (!anime4k_enabled_) {
    return frame_target;
  }

  if (!anime4k_processor_) {
    anime4k_processor_ = std::make_unique<D3D11Anime4KProcessor>(
        d3d_11_device_.Get(), d3d_11_device_context_.Get());
  }
  if (!anime4k_processor_->EnsureSize(width_, height_)) {
    return frame_target;
  }

  anime4k_frame_pending_ = true;
  return anime4k_processor_->input_texture();
}

void D3D11Renderer::SetSize(int32_t width, int32_t height) {
  if (width == width_ && height == height_) return;
  width_ = width;
  height_ = height;
  if (anime4k_processor_) {
    anime4k_processor_->EnsureSize(width_, height_);
  }
  if (mailbox_swap_chain_) {
    const HRESULT hr = mailbox_swap_chain_->Resize(width_, height_);
    if (FAILED(hr)) {
      std::cout << "media_kit: D3D11Renderer: mailbox resize failed (hr=0x"
                << std::hex << hr << std::dec << ")" << std::endl;
    }
  }
  if (fixed_handle_bridge_) {
    const HRESULT hr = fixed_handle_bridge_->Resize(width_, height_);
    if (FAILED(hr)) {
      std::cout << "media_kit: D3D11Renderer: fixed handle resize failed "
                   "(hr=0x"
                << std::hex << hr << std::dec << ")" << std::endl;
    }
  }
}

void D3D11Renderer::SetAnime4KEnabled(bool enabled) {
  anime4k_enabled_ = enabled;
  anime4k_frame_pending_ = false;
  if (!enabled && anime4k_processor_) {
    anime4k_processor_->Reset();
  }
}

bool D3D11Renderer::ProducerCommit() {
  if (mailbox_swap_chain_ || fixed_handle_bridge_) {
    if (anime4k_frame_pending_ && anime4k_processor_ &&
        anime4k_processor_->input_texture()) {
      ID3D11Texture2D* output = FrameRenderTarget();
      if (output && !anime4k_processor_->Process(output)) {
        d3d_11_device_context_->CopyResource(
            output, anime4k_processor_->input_texture());
        std::cout << "media_kit: D3D11Renderer: Anime4K pass failed; "
                     "submitting unprocessed frame."
                  << std::endl;
      }
    }
    anime4k_frame_pending_ = false;
    media_kit_video::PerformanceMetrics::Instance().AddProducerCommit();
    return mailbox_swap_chain_ ? mailbox_swap_chain_->ProducerCommit()
                               : fixed_handle_bridge_->ProducerCommit();
  }
  return false;
}

HANDLE D3D11Renderer::ConsumerAcquire() {
  auto& metrics = media_kit_video::PerformanceMetrics::Instance();
  const bool collect_metrics = metrics.enabled();
  std::chrono::steady_clock::time_point start;
  if (collect_metrics) start = std::chrono::steady_clock::now();
  const auto handle = mailbox_swap_chain_
                          ? mailbox_swap_chain_->ConsumerAcquire()
                          : fixed_handle_bridge_
                                ? fixed_handle_bridge_->ConsumerAcquire()
                                : nullptr;
  if (collect_metrics) {
    const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now() - start);
    metrics.ObserveConsumerAcquireDuration(
        static_cast<uint64_t>(elapsed.count() < 0 ? 0 : elapsed.count()));
  }
  return handle;
}

void D3D11Renderer::ConsumerRelease(HANDLE handle) {
  if (mailbox_swap_chain_) {
    mailbox_swap_chain_->ConsumerRelease(handle);
  }
}

HANDLE D3D11Renderer::ReadHandleSnapshot() const {
  if (mailbox_swap_chain_) return mailbox_swap_chain_->ReadHandleSnapshot();
  return fixed_handle_bridge_ ? fixed_handle_bridge_->ReadHandleSnapshot()
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
    int applied_priority = media_kit_video::kUnknownGpuThreadPriority;
    const HRESULT priority_hr =
        media_kit_video::ApplyGpuThreadPriority(dxgi_device.Get(),
                                                &applied_priority);
    media_kit_video::PerformanceMetrics::Instance().SetGpuPriorityResult(
        media_kit_video::g_gpu_thread_priority.load(), applied_priority,
        static_cast<long>(priority_hr));
    Microsoft::WRL::ComPtr<IDXGIAdapter> device_adapter;
    if (SUCCEEDED(dxgi_device->GetAdapter(&device_adapter)) &&
        device_adapter) {
      DXGI_ADAPTER_DESC desc = {};
      if (SUCCEEDED(device_adapter->GetDesc(&desc))) {
        int length = ::WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1,
                                           nullptr, 0, nullptr, nullptr);
        if (length > 1) {
          std::string description(static_cast<size_t>(length), '\0');
          ::WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1,
                                description.data(), length, nullptr, nullptr);
          description.resize(static_cast<size_t>(length - 1));
          gpu_adapter_ = description;
        }
      }
    }
    media_kit_video::PerformanceMetrics::Instance().SetGpuAdapter(
        gpu_adapter_);
  }

  return true;
}

void D3D11Renderer::SetGPUThreadPriority(int priority) {
  media_kit_video::g_gpu_thread_priority.store(
      media_kit_video::NormalizeGpuThreadPriority(priority));
  Microsoft::WRL::ComPtr<IDXGIDevice> dxgi_device;
  if (d3d_11_device_ &&
      SUCCEEDED(d3d_11_device_.As(&dxgi_device)) && dxgi_device) {
    int applied_priority = media_kit_video::kUnknownGpuThreadPriority;
    const HRESULT priority_hr =
        media_kit_video::ApplyGpuThreadPriority(dxgi_device.Get(),
                                                &applied_priority);
    media_kit_video::PerformanceMetrics::Instance().SetGpuPriorityResult(
        media_kit_video::g_gpu_thread_priority.load(), applied_priority,
        static_cast<long>(priority_hr));
  }
}

bool D3D11Renderer::CreateFrameBridge() {
  if (output_mode_ == media_kit_video::VideoOutputMode::kFixedHandleCopy) {
    FixedHandleTextureBridge* raw = nullptr;
    const HRESULT hr = FixedHandleTextureBridge::Create(
        d3d_11_device_.Get(), width_, height_, &raw);
    if (FAILED(hr)) {
      std::cout << "media_kit: D3D11Renderer: "
                   "FixedHandleTextureBridge::Create failed (hr=0x"
                << std::hex << hr << std::dec << ")" << std::endl;
      return false;
    }
    fixed_handle_bridge_.reset(raw);
    return true;
  }

  MailboxSwapChain* raw = nullptr;
  const bool non_blocking =
      output_mode_ == media_kit_video::VideoOutputMode::kNonBlockingMailbox;
  const HRESULT hr = MailboxSwapChain::Create(
      d3d_11_device_.Get(), width_, height_, non_blocking, &raw);
  if (FAILED(hr)) {
    std::cout << "media_kit: D3D11Renderer: MailboxSwapChain::Create failed "
                 "(hr=0x"
              << std::hex << hr << std::dec << ")" << std::endl;
    return false;
  }
  mailbox_swap_chain_.Attach(raw);
  return true;
}

ID3D11Texture2D* D3D11Renderer::FrameRenderTarget() {
  if (mailbox_swap_chain_) return mailbox_swap_chain_->RenderTarget();
  return fixed_handle_bridge_ ? fixed_handle_bridge_->RenderTarget() : nullptr;
}

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
#include <functional>
#include <memory>
#include <mutex>

#include "d3d11_anime4k_processor.h"
#include "fixed_handle_texture_bridge.h"
#include "mailbox_swap_chain.h"
#include "video_output_mode.h"

class D3D11Renderer {
 public:
  struct ConsumerLease {
    HANDLE handle = nullptr;
    int slot = -1;
    uint64_t submission_id = 0;
    Microsoft::WRL::ComPtr<MailboxSwapChain> mailbox;
    Microsoft::WRL::ComPtr<ID3D11Texture2D> texture;
  };

  int32_t width() const { return width_; }
  int32_t height() const { return height_; }

  ID3D11Device* device() const { return d3d_11_device_.Get(); }
  ID3D11Texture2D* render_target();

  explicit D3D11Renderer(int32_t width,
                         int32_t height,
                         IDXGIAdapter* flutter_adapter,
                         media_kit_video::VideoOutputMode output_mode,
                         bool use_consumer_leases);
  ~D3D11Renderer();

  void SetSize(int32_t width, int32_t height);
  void SetAnime4KEnabled(bool enabled);
  void SetGPUThreadPriority(int priority);
  // The caller keeps this lock across render_target(), mpv rendering and
  // ProducerCommit() so Flutter's descriptor callback cannot interleave D3D11
  // immediate-context commands with producer command submission.
  std::unique_lock<std::mutex> AcquireRenderLock() {
    return std::unique_lock<std::mutex>(render_mutex_);
  }
  bool ProducerCommit();
  HANDLE ConsumerAcquire();
  ConsumerLease* ConsumerAcquireLease();
  static void ReleaseConsumerLease(void* context);
  void ConsumerHandleOpened(HANDLE handle);
  void SetFrameAvailableCallback(std::function<void()> callback);
  HANDLE ReadHandleSnapshot() const;
  bool UsesNonBlockingMailbox() const {
    return output_mode_ ==
           media_kit_video::VideoOutputMode::kNonBlockingMailbox;
  }
  bool ShouldSkipRendering() const { return UsesNonBlockingMailbox(); }

 private:
  bool CreateD3D11Device(IDXGIAdapter* flutter_adapter);
  bool CreateFrameBridge();
  ID3D11Texture2D* FrameRenderTarget();

  int32_t width_ = 1;
  int32_t height_ = 1;

  Microsoft::WRL::ComPtr<ID3D11Device> d3d_11_device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> d3d_11_device_context_;
  Microsoft::WRL::ComPtr<MailboxSwapChain> mailbox_swap_chain_;
  std::unique_ptr<FixedHandleTextureBridge> fixed_handle_bridge_;
  std::unique_ptr<D3D11Anime4KProcessor> anime4k_processor_;
  std::mutex render_mutex_;
  media_kit_video::VideoOutputMode output_mode_ =
      media_kit_video::kDefaultVideoOutputMode;
  bool use_consumer_leases_ = false;
  bool anime4k_enabled_ = false;
  bool anime4k_frame_pending_ = false;
};

#endif  // D3D11_RENDERER_H_

// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright (c) 2026 Predidit.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#ifndef MAILBOX_SWAP_CHAIN_H_
#define MAILBOX_SWAP_CHAIN_H_

#include <Windows.h>
#include <d3d11.h>
#include <d3d11_4.h>
#include <dxgi.h>
#include <wrl.h>

#include <atomic>
#include <cstdint>
#include <mutex>

// A small 4-slot mailbox of BGRA8 D3D11 textures shared between mpv's producer
// thread and Flutter's GpuSurfaceTexture consumer.
class MailboxSwapChain final : public IDXGISwapChain {
 public:
  static HRESULT Create(ID3D11Device* device,
                        int32_t width,
                        int32_t height,
                        bool non_blocking,
                        MailboxSwapChain** out);

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                           void** ppv) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;

  HRESULT STDMETHODCALLTYPE SetPrivateData(REFGUID, UINT,
                                           const void*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE SetPrivateDataInterface(REFGUID,
                                                    const IUnknown*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE GetPrivateData(REFGUID, UINT*, void*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE GetParent(REFIID, void**) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE GetDevice(REFIID, void**) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE Present(UINT, UINT) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE GetBuffer(UINT Buffer,
                                      REFIID riid,
                                      void** ppSurface) override;
  HRESULT STDMETHODCALLTYPE GetDesc(DXGI_SWAP_CHAIN_DESC* pDesc) override;
  HRESULT STDMETHODCALLTYPE SetFullscreenState(BOOL,
                                               IDXGIOutput*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE GetFullscreenState(BOOL*,
                                               IDXGIOutput**) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE ResizeBuffers(UINT, UINT, UINT, DXGI_FORMAT,
                                          UINT) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE ResizeTarget(const DXGI_MODE_DESC*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE GetContainingOutput(IDXGIOutput**) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE GetFrameStatistics(
      DXGI_FRAME_STATISTICS*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE GetLastPresentCount(UINT*) override {
    return E_NOTIMPL;
  }

  ID3D11Texture2D* RenderTarget();
  bool ProducerCommit();
  HANDLE ConsumerAcquire();
  void ConsumerRelease(HANDLE handle);
  HRESULT Resize(int32_t width, int32_t height);

  HANDLE ReadHandleSnapshot();

  int32_t width() const { return width_; }
  int32_t height() const { return height_; }

 private:
  MailboxSwapChain() = default;
  ~MailboxSwapChain();

  MailboxSwapChain(const MailboxSwapChain&) = delete;
  MailboxSwapChain& operator=(const MailboxSwapChain&) = delete;

  HRESULT AllocateSlots();
  void ReleaseSlots();
  HRESULT WaitForSlot(int slot);
  ID3D11Texture2D* RenderTargetNonBlocking();
  bool ProducerCommitNonBlocking();
  bool PromoteCompletedFrames();
  bool TakePublishedFrame();
  void ResetNonBlockingState();

  enum class SlotState {
    kFree,
    kWriting,
    kPending,
    kPublished,
    kRetired,
  };

  struct TextureSlot {
    Microsoft::WRL::ComPtr<ID3D11Texture2D> texture;
    HANDLE shared_handle = nullptr;
    Microsoft::WRL::ComPtr<ID3D11Fence> fence;
    uint64_t fence_value = 0;
    uint64_t submission_id = 0;
    SlotState state = SlotState::kFree;
  };

  ID3D11Device* device_ = nullptr;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext4> context4_;

  int32_t width_ = 1;
  int32_t height_ = 1;

  TextureSlot slots_[4];

  std::mutex slots_mutex_;
  HANDLE fence_event_ = nullptr;
  bool non_blocking_ = false;

  std::atomic<bool> has_completed_frame_{false};
  std::atomic<int> latest_completed_slot_{-1};
  uint64_t next_submission_id_ = 0;
  bool published_frame_pending_ = false;
  int next_write_slot_ = 0;
  int write_slot_ = -1;

  std::atomic<ULONG> ref_count_{1u};
};

#endif  // MAILBOX_SWAP_CHAIN_H_

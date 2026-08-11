// This file is a part of media_kit.

#ifndef FIXED_HANDLE_TEXTURE_BRIDGE_H_
#define FIXED_HANDLE_TEXTURE_BRIDGE_H_

#include <Windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <wrl.h>

#include <atomic>
#include <cstdint>

// Renders into a private texture, then copies the newest unconsumed frame into
// one shared texture when Flutter requests the descriptor. The shared HANDLE
// remains stable until the video is resized.
class FixedHandleTextureBridge final {
 public:
  static HRESULT Create(ID3D11Device* device,
                        int32_t width,
                        int32_t height,
                        FixedHandleTextureBridge** out);

  ~FixedHandleTextureBridge();

  ID3D11Texture2D* RenderTarget() const { return render_texture_.Get(); }
  bool ProducerCommit();
  HANDLE ConsumerAcquire();
  HANDLE ReadHandleSnapshot() const {
    return shared_handle_.load(std::memory_order_acquire);
  }
  HRESULT Resize(int32_t width, int32_t height);

 private:
  FixedHandleTextureBridge() = default;
  FixedHandleTextureBridge(const FixedHandleTextureBridge&) = delete;
  FixedHandleTextureBridge& operator=(const FixedHandleTextureBridge&) = delete;

  HRESULT AllocateTextures();
  void ReleaseTextures();

  ID3D11Device* device_ = nullptr;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> render_texture_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> shared_texture_;
  std::atomic<HANDLE> shared_handle_{nullptr};
  std::atomic<uint64_t> produced_generation_{0};
  std::atomic<uint64_t> copied_generation_{0};
  int32_t width_ = 1;
  int32_t height_ = 1;
};

#endif  // FIXED_HANDLE_TEXTURE_BRIDGE_H_

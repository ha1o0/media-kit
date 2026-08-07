// This file is a part of media_kit.

#ifndef GPU_THREAD_PRIORITY_H_
#define GPU_THREAD_PRIORITY_H_

#include <Windows.h>
#include <dxgi.h>

#include <atomic>

namespace media_kit_video {

constexpr int kDefaultGpuThreadPriority = 5;
constexpr int kMinGpuThreadPriority = -7;
constexpr int kMaxGpuThreadPriority = 7;
constexpr int kUnknownGpuThreadPriority = 100;

inline std::atomic<int> g_gpu_thread_priority{kDefaultGpuThreadPriority};

inline int NormalizeGpuThreadPriority(int priority) {
  if (priority < kMinGpuThreadPriority) return kMinGpuThreadPriority;
  if (priority > kMaxGpuThreadPriority) return kMaxGpuThreadPriority;
  return priority;
}

inline HRESULT ApplyGpuThreadPriority(IDXGIDevice* device,
                                      int* applied_priority = nullptr) {
  if (device == nullptr) return E_INVALIDARG;
  const auto requested =
      NormalizeGpuThreadPriority(g_gpu_thread_priority.load());
  const HRESULT hr = device->SetGPUThreadPriority(requested);
  if (SUCCEEDED(hr) && applied_priority != nullptr) {
    INT priority = requested;
    if (SUCCEEDED(device->GetGPUThreadPriority(&priority))) {
      *applied_priority = static_cast<int>(priority);
    } else {
      *applied_priority = requested;
    }
  }
  return hr;
}

}  // namespace media_kit_video

#endif  // GPU_THREAD_PRIORITY_H_

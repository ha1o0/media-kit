// This file is a part of media_kit.

#ifndef GPU_THREAD_PRIORITY_H_
#define GPU_THREAD_PRIORITY_H_

#include <Windows.h>
#include <dxgi.h>

#include <atomic>

namespace media_kit_video {

// DXGI documents 0 as normal priority. Raising only the video device can
// starve Flutter's compositor under sustained GPU load on hybrid laptops.
constexpr int kDefaultGpuThreadPriority = 0;
constexpr int kMinGpuThreadPriority = -7;
constexpr int kMaxGpuThreadPriority = 7;

inline std::atomic<int> g_gpu_thread_priority{kDefaultGpuThreadPriority};

inline int NormalizeGpuThreadPriority(int priority) {
  if (priority < kMinGpuThreadPriority) return kMinGpuThreadPriority;
  if (priority > kMaxGpuThreadPriority) return kMaxGpuThreadPriority;
  return priority;
}

inline void ApplyGpuThreadPriority(IDXGIDevice* device) {
  if (device == nullptr) return;
  device->SetGPUThreadPriority(
      NormalizeGpuThreadPriority(g_gpu_thread_priority.load()));
}

}  // namespace media_kit_video

#endif  // GPU_THREAD_PRIORITY_H_

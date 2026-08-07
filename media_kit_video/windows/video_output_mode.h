// This file is a part of media_kit.

#ifndef VIDEO_OUTPUT_MODE_H_
#define VIDEO_OUTPUT_MODE_H_

#include <atomic>

namespace media_kit_video {

enum class VideoOutputMode : int {
  kBlockingMailbox = 0,
  kNonBlockingMailbox = 1,
  kFixedHandleCopy = 2,
};

constexpr VideoOutputMode kDefaultVideoOutputMode =
    VideoOutputMode::kBlockingMailbox;

inline std::atomic<int> g_video_output_mode{
    static_cast<int>(kDefaultVideoOutputMode)};

inline VideoOutputMode NormalizeVideoOutputMode(int value) {
  switch (value) {
    case static_cast<int>(VideoOutputMode::kNonBlockingMailbox):
      return VideoOutputMode::kNonBlockingMailbox;
    case static_cast<int>(VideoOutputMode::kFixedHandleCopy):
      return VideoOutputMode::kFixedHandleCopy;
    case static_cast<int>(VideoOutputMode::kBlockingMailbox):
    default:
      return VideoOutputMode::kBlockingMailbox;
  }
}

inline VideoOutputMode GetVideoOutputMode() {
  return NormalizeVideoOutputMode(g_video_output_mode.load());
}

}  // namespace media_kit_video

#endif  // VIDEO_OUTPUT_MODE_H_

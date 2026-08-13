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
    VideoOutputMode::kFixedHandleCopy;

inline std::atomic<int> g_video_output_mode{
    static_cast<int>(kDefaultVideoOutputMode)};

inline VideoOutputMode NormalizeVideoOutputMode(int value) {
  switch (value) {
    case static_cast<int>(VideoOutputMode::kBlockingMailbox):
      return VideoOutputMode::kBlockingMailbox;
    case static_cast<int>(VideoOutputMode::kNonBlockingMailbox):
      return VideoOutputMode::kNonBlockingMailbox;
    case static_cast<int>(VideoOutputMode::kFixedHandleCopy):
    default:
      return VideoOutputMode::kFixedHandleCopy;
  }
}

inline VideoOutputMode GetVideoOutputMode() {
  return NormalizeVideoOutputMode(g_video_output_mode.load());
}

inline const char* VideoOutputModeName(VideoOutputMode mode) {
  switch (mode) {
    case VideoOutputMode::kNonBlockingMailbox:
      return "non-blocking-mailbox-experimental";
    case VideoOutputMode::kFixedHandleCopy:
      return "fixed-handle-copy";
    case VideoOutputMode::kBlockingMailbox:
    default:
      return "blocking-mailbox-legacy";
  }
}

}  // namespace media_kit_video

#endif  // VIDEO_OUTPUT_MODE_H_

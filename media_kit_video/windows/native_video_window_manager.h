// This file is a part of media_kit.

#ifndef NATIVE_VIDEO_WINDOW_MANAGER_H_
#define NATIVE_VIDEO_WINDOW_MANAGER_H_

#include <Windows.h>

#include <cstdint>
#include <unordered_map>

#include <flutter/plugin_registrar_windows.h>

namespace media_kit_video {

// Owns the non-activating top-level windows used by mpv's native Windows VO.
// Each window is kept immediately behind the Flutter host so Flutter controls
// can remain above the video without relying on Windows Platform Views.
class NativeVideoWindowManager {
 public:
  explicit NativeVideoWindowManager(
      flutter::PluginRegistrarWindows* registrar);
  ~NativeVideoWindowManager();

  NativeVideoWindowManager(const NativeVideoWindowManager&) = delete;
  NativeVideoWindowManager& operator=(const NativeVideoWindowManager&) =
      delete;

  HWND Create(int64_t handle, bool video_above_flutter = false);
  int SetBounds(int64_t handle,
                double x,
                double y,
                double width,
                double height,
                bool visible);
  void Dispose(int64_t handle);
  void HideAll();
  bool HasWindows() const { return !entries_.empty(); }
  void SyncAll();
  void SyncAllForHostWindowPos(const WINDOWPOS& window_pos);

 private:
  struct Entry {
    HWND window = nullptr;
    double x = 0.0;
    double y = 0.0;
    double width = 0.0;
    double height = 0.0;
    bool visible = false;
    bool video_above_flutter = false;
    ULONGLONG resync_deadline = 0;
    bool syncing = false;
  };

  bool EnsureWindowClass();
  void ScheduleResync(Entry& entry);
  void RefreshFlutterWindow();
  int Sync(Entry& entry);
  static LRESULT CALLBACK WindowProc(HWND window,
                                     UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam);

  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  HWND flutter_window_ = nullptr;
  std::unordered_map<int64_t, Entry> entries_;
  bool owns_window_class_ = false;
  bool shutdown_hidden_ = false;
};

}  // namespace media_kit_video

#endif  // NATIVE_VIDEO_WINDOW_MANAGER_H_

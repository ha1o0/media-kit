// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.
#ifndef MEDIA_KIT_VIDEO_PLUGIN_H_
#define MEDIA_KIT_VIDEO_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <Windows.h>
#include <functional>
#include <mutex>
#include <optional>
#include <queue>

#include "video_output_manager.h"
#include "native_video_window_manager.h"

namespace media_kit_video {

class MediaKitVideoPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  MediaKitVideoPlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~MediaKitVideoPlugin();

  MediaKitVideoPlugin(const MediaKitVideoPlugin&) = delete;
  MediaKitVideoPlugin& operator=(const MediaKitVideoPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void RunOnMainThread(std::function<void()> task);
  std::optional<LRESULT> HandleWindowProc(HWND hwnd,
                                          UINT message,
                                          WPARAM wparam,
                                          LPARAM lparam);
  void ScheduleNativeWindowSync();
  void ProcessMainThreadTasks();
  
  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_ =
      nullptr;
  std::unique_ptr<NativeVideoWindowManager> native_video_window_manager_ =
      nullptr;
  std::unique_ptr<VideoOutputManager> video_output_manager_ = nullptr;
  HWND flutter_window_ = nullptr;
  int window_proc_id_ = -1;
  bool native_window_sync_pending_ = false;
  std::queue<std::function<void()>> main_thread_tasks_;
  std::mutex main_thread_tasks_mutex_;
};

}  // namespace media_kit_video

#endif  // MEDIA_KIT_VIDEO_PLUGIN_H_

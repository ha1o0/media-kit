// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.
#include "media_kit_video_plugin.h"
#include "utils.h"
#include "gpu_thread_priority.h"
#include "performance_metrics.h"
#include "video_output_mode.h"

#include <Windows.h>

namespace media_kit_video {

namespace {

const char* VideoOutputModeName(int mode) {
  if (mode == 3) return "software";
  switch (NormalizeVideoOutputMode(mode)) {
    case VideoOutputMode::kNonBlockingMailbox:
      return "nonBlockingMailbox";
    case VideoOutputMode::kFixedHandleCopy:
      return "fixedHandleCopy";
    case VideoOutputMode::kBlockingMailbox:
    default:
      return "blockingMailbox";
  }
}

void UpdateDisplayMetrics(HWND window) {
  if (!window) return;

  RECT rect = {};
  ::GetClientRect(window, &rect);
  int dpi = 0;
  using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
  const auto user32 = ::GetModuleHandleW(L"user32.dll");
  const auto get_dpi_for_window = user32
                                      ? reinterpret_cast<GetDpiForWindowFn>(
                                            ::GetProcAddress(
                                                user32, "GetDpiForWindow"))
                                      : nullptr;
  if (get_dpi_for_window) {
    dpi = static_cast<int>(get_dpi_for_window(window));
  }

  int refresh_rate = 0;
  const auto monitor = ::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFOEXW monitor_info = {};
  monitor_info.cbSize = sizeof(monitor_info);
  if (monitor && ::GetMonitorInfoW(monitor, &monitor_info)) {
    DEVMODEW mode = {};
    mode.dmSize = sizeof(mode);
    if (::EnumDisplaySettingsW(monitor_info.szDevice, ENUM_CURRENT_SETTINGS,
                               &mode)) {
      refresh_rate = static_cast<int>(mode.dmDisplayFrequency);
    }
  }

  PerformanceMetrics::Instance().SetDisplayInfo(
      static_cast<int64_t>(rect.right - rect.left),
      static_cast<int64_t>(rect.bottom - rect.top), dpi, refresh_rate);
}

flutter::EncodableValue BuildPerformanceMetricsValue(
    const PerformanceMetrics::Snapshot& snapshot,
    int configured_mode,
    bool mpv_snapshot_available,
    const std::vector<VideoOutputPerformanceSnapshot>& outputs) {
  using flutter::EncodableList;
  using flutter::EncodableMap;
  using flutter::EncodableValue;

  const auto value = [](uint64_t input) {
    return EncodableValue(static_cast<int64_t>(input));
  };
  EncodableMap counters{
      {EncodableValue("renderRequests"), value(snapshot.render_requests)},
      {EncodableValue("renderRequestsCoalesced"),
       value(snapshot.render_request_coalesced)},
      {EncodableValue("renderTasks"), value(snapshot.render_tasks)},
      {EncodableValue("renderQueueWaitTotalUs"),
       value(snapshot.render_queue_wait_total_us)},
      {EncodableValue("renderQueueWaitMaxUs"),
       value(snapshot.render_queue_wait_max_us)},
      {EncodableValue("mpvRenderCalls"), value(snapshot.mpv_render_calls)},
      {EncodableValue("skipRenderingCalls"),
       value(snapshot.skip_rendering_calls)},
      {EncodableValue("mpvRenderTotalUs"),
       value(snapshot.mpv_render_total_us)},
      {EncodableValue("mpvRenderMaxUs"), value(snapshot.mpv_render_max_us)},
      {EncodableValue("producerCommitCalls"),
       value(snapshot.producer_commits)},
      {EncodableValue("producerCommitFailures"),
       value(snapshot.producer_commit_failures)},
      {EncodableValue("frameAvailableMarks"),
       value(snapshot.frame_available_marks)},
      {EncodableValue("frameAvailableFailures"),
       value(snapshot.frame_available_failures)},
      {EncodableValue("frameAvailableTotalUs"),
       value(snapshot.frame_available_total_us)},
      {EncodableValue("frameAvailableMaxUs"),
       value(snapshot.frame_available_max_us)},
      {EncodableValue("flutterTextureCallbacks"),
       value(snapshot.flutter_texture_callbacks)},
      {EncodableValue("flutterTextureCallbackTotalUs"),
       value(snapshot.flutter_texture_callback_total_us)},
      {EncodableValue("flutterTextureCallbackMaxUs"),
       value(snapshot.flutter_texture_callback_max_us)},
      {EncodableValue("consumerAcquireCalls"),
       value(snapshot.consumer_acquire_calls)},
      {EncodableValue("consumerAcquireTotalUs"),
       value(snapshot.consumer_acquire_total_us)},
      {EncodableValue("consumerAcquireMaxUs"),
       value(snapshot.consumer_acquire_max_us)},
      {EncodableValue("textureCallbackNoHandle"),
       value(snapshot.texture_callback_no_handle)},
      {EncodableValue("textureHandleChanges"),
       value(snapshot.texture_handle_changes)},
      {EncodableValue("textureRegistrations"),
       value(snapshot.texture_registrations)},
      {EncodableValue("textureResizes"), value(snapshot.texture_resizes)},
      {EncodableValue("textureUnregisters"),
       value(snapshot.texture_unregisters)},
      {EncodableValue("flushes"), value(snapshot.flushes)},
      {EncodableValue("blockingFenceWaits"),
       value(snapshot.blocking_fence_waits)},
      {EncodableValue("blockingWaitTotalUs"),
       value(snapshot.blocking_wait_total_us)},
      {EncodableValue("blockingWaitMaxUs"),
       value(snapshot.blocking_wait_max_us)},
      {EncodableValue("nonBlockingFencePolls"),
       value(snapshot.nonblocking_fence_polls)},
      {EncodableValue("nonBlockingFenceIncomplete"),
       value(snapshot.nonblocking_fence_incomplete)},
      {EncodableValue("publishes"), value(snapshot.publishes)},
      {EncodableValue("pendingSlotsCurrent"),
       value(snapshot.pending_slots_current)},
      {EncodableValue("pendingSlotsMax"),
       value(snapshot.pending_slots_max)},
      {EncodableValue("mailboxFull"), value(snapshot.mailbox_full)},
      {EncodableValue("fixedHandleCopies"),
       value(snapshot.fixed_handle_copies)},
      {EncodableValue("renderTargetMisses"),
       value(snapshot.render_target_misses)},
  };

  EncodableList render_buckets;
  for (const auto bucket : snapshot.mpv_render_buckets) {
    render_buckets.emplace_back(value(bucket));
  }
  counters.emplace(EncodableValue("mpvRenderTimeBuckets"),
                   EncodableValue(render_buckets));

  EncodableList mpv_outputs;
  int output_index = 0;
  for (const auto& output : outputs) {
    EncodableMap properties;
    for (const auto& property : output.mpv_properties) {
      properties.emplace(EncodableValue(property.first),
                         EncodableValue(property.second));
    }
    mpv_outputs.emplace_back(EncodableMap{
        {EncodableValue("outputIndex"), EncodableValue(output_index++)},
        {EncodableValue("properties"), EncodableValue(properties)},
    });
  }

  const auto actual_mode = snapshot.output_mode >= 0
                               ? snapshot.output_mode
                               : configured_mode;
  return EncodableValue(EncodableMap{
      {EncodableValue("schemaVersion"), EncodableValue(1)},
      {EncodableValue("enabled"), EncodableValue(snapshot.enabled)},
      {EncodableValue("enabledElapsedMs"),
       value(snapshot.enabled_elapsed_ms)},
      {EncodableValue("configuredOutputMode"),
       EncodableValue(VideoOutputModeName(configured_mode))},
      {EncodableValue("actualOutputMode"),
       EncodableValue(VideoOutputModeName(actual_mode))},
      {EncodableValue("activeOutputs"),
       EncodableValue(snapshot.active_outputs)},
      {EncodableValue("hardwareAcceleration"),
       EncodableValue(snapshot.hardware_acceleration)},
      {EncodableValue("renderBackend"),
       EncodableValue(snapshot.render_backend)},
      {EncodableValue("anime4kEnabled"),
       EncodableValue(snapshot.anime4k_enabled)},
      {EncodableValue("textureWidth"),
       EncodableValue(snapshot.texture_width)},
      {EncodableValue("textureHeight"),
       EncodableValue(snapshot.texture_height)},
      {EncodableValue("windowWidth"),
       EncodableValue(snapshot.window_width)},
      {EncodableValue("windowHeight"),
       EncodableValue(snapshot.window_height)},
      {EncodableValue("displayDpi"), EncodableValue(snapshot.display_dpi)},
      {EncodableValue("displayRefreshRate"),
       EncodableValue(snapshot.display_refresh_rate)},
      {EncodableValue("gpuAdapter"), EncodableValue(snapshot.gpu_adapter)},
      {EncodableValue("gpuPriorityRequested"),
       EncodableValue(snapshot.gpu_priority_requested)},
      {EncodableValue("gpuPriorityApplied"),
       EncodableValue(snapshot.gpu_priority_applied)},
      {EncodableValue("gpuPrioritySetHresult"),
       EncodableValue(static_cast<int64_t>(snapshot.gpu_priority_hresult))},
      {EncodableValue("gpuPrioritySetSucceeded"),
       EncodableValue(SUCCEEDED(snapshot.gpu_priority_hresult))},
      {EncodableValue("counters"), EncodableValue(counters)},
      {EncodableValue("mpvOutputs"), EncodableValue(mpv_outputs)},
      {EncodableValue("mpvSnapshotAvailable"),
       EncodableValue(mpv_snapshot_available)},
  });
}

}  // namespace

MediaKitVideoPlugin* MediaKitVideoPlugin::instance_ = nullptr;

void MediaKitVideoPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<MediaKitVideoPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

MediaKitVideoPlugin::MediaKitVideoPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar),
      video_output_manager_(std::make_unique<VideoOutputManager>(registrar)) {
  instance_ = this;
  flutter_window_ =
      ::GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT);
  original_window_proc_ = reinterpret_cast<WNDPROC>(
      ::SetWindowLongPtr(flutter_window_, GWLP_WNDPROC,
                         reinterpret_cast<LONG_PTR>(WindowProcDelegate)));

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "com.alexmercerind/media_kit_video",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([&](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

MediaKitVideoPlugin::~MediaKitVideoPlugin() {
  if (flutter_window_ && original_window_proc_) {
    ::SetWindowLongPtr(flutter_window_, GWLP_WNDPROC,
                       reinterpret_cast<LONG_PTR>(original_window_proc_));
  }
  if (instance_ == this) {
    instance_ = nullptr;
  }
}

void MediaKitVideoPlugin::RunOnMainThread(std::function<void()> task) {
  if (!flutter_window_) {
    return;
  }

  {
    std::lock_guard<std::mutex> lock(main_thread_tasks_mutex_);
    main_thread_tasks_.push(std::move(task));
  }

  ::PostMessage(flutter_window_, kMainThreadTaskMessage, 0, 0);
}

LRESULT CALLBACK MediaKitVideoPlugin::WindowProcDelegate(HWND hwnd,
                                                         UINT message,
                                                         WPARAM wParam,
                                                         LPARAM lParam) {
  if (message == kMainThreadTaskMessage && instance_) {
    instance_->ProcessMainThreadTasks();
    return 0;
  }

  if (instance_ && instance_->original_window_proc_) {
    return ::CallWindowProc(instance_->original_window_proc_, hwnd, message,
                            wParam, lParam);
  }

  return ::DefWindowProc(hwnd, message, wParam, lParam);
}

void MediaKitVideoPlugin::ProcessMainThreadTasks() {
  std::queue<std::function<void()>> tasks_to_execute;

  {
    std::lock_guard<std::mutex> lock(main_thread_tasks_mutex_);
    tasks_to_execute.swap(main_thread_tasks_);
  }

  while (!tasks_to_execute.empty()) {
    auto task = std::move(tasks_to_execute.front());
    tasks_to_execute.pop();

    try {
      task();
    } catch (...) {
    }
  }
}

void MediaKitVideoPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("VideoOutputManager.Create") == 0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    auto handle =
        std::get<std::string>(arguments[flutter::EncodableValue("handle")]);
    auto configuration = std::get<flutter::EncodableMap>(
        arguments[flutter::EncodableValue("configuration")]);

    auto handle_value = std::stoll(handle);
    auto configuration_value = VideoOutputConfiguration{};

    auto configuration_width =
        std::get<std::string>(configuration[flutter::EncodableValue("width")]);
    auto configuration_height =
        std::get<std::string>(configuration[flutter::EncodableValue("height")]);
    auto configuration_enable_hardware_acceleration = std::get<bool>(
        configuration[flutter::EncodableValue("enableHardwareAcceleration")]);
    auto configuration_render_backend = std::get<std::string>(
        configuration[flutter::EncodableValue("renderBackend")]);
    if (configuration_width.compare("null") != 0) {
      configuration_value.width =
          static_cast<int64_t>(std::stoll(configuration_width.c_str()));
    }
    if (configuration_height.compare("null") != 0) {
      configuration_value.height =
          static_cast<int64_t>(std::stoll(configuration_height.c_str()));
    }
    configuration_value.enable_hardware_acceleration =
        configuration_enable_hardware_acceleration;
    if (configuration_render_backend.compare("null") != 0) {
      configuration_value.render_backend = configuration_render_backend;
    }

    video_output_manager_->Create(
        handle_value, configuration_value,
        [this, handle = handle_value](auto id, auto width, auto height) {
          RunOnMainThread([=]() {
            channel_->InvokeMethod(
                "VideoOutput.Resize",
                std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                    {
                        flutter::EncodableValue("handle"),
                        flutter::EncodableValue(handle),
                    },
                    {
                        flutter::EncodableValue("id"),
                        flutter::EncodableValue(id),
                    },
                    {
                        flutter::EncodableValue("rect"),
                        flutter::EncodableValue(flutter::EncodableMap{
                            {
                                flutter::EncodableValue("left"),
                                flutter::EncodableValue(0),
                            },
                            {
                                flutter::EncodableValue("top"),
                                flutter::EncodableValue(0),
                            },
                            {
                                flutter::EncodableValue("width"),
                                flutter::EncodableValue(width),
                            },
                            {
                                flutter::EncodableValue("height"),
                                flutter::EncodableValue(height),
                            },
                        }),
                    },
                }),
                nullptr);
          });
        });
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("VideoOutputManager.Dispose") ==
             0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    auto handle =
        std::get<std::string>(arguments[flutter::EncodableValue("handle")]);
    auto handle_value = static_cast<int64_t>(std::stoll(handle.c_str()));
    video_output_manager_->Dispose(handle_value);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("VideoOutputManager.SetSize") ==
             0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    auto handle =
        std::get<std::string>(arguments[flutter::EncodableValue("handle")]);
    auto width =
        std::get<std::string>(arguments[flutter::EncodableValue("width")]);
    auto height =
        std::get<std::string>(arguments[flutter::EncodableValue("height")]);
    auto handle_value = static_cast<int64_t>(std::stoll(handle.c_str()));
    auto width_value = std::optional<int64_t>{};
    auto height_value = std::optional<int64_t>{};
    if (width.compare("null") != 0) {
      width_value = static_cast<int64_t>(std::stoll(width.c_str()));
    }
    if (height.compare("null") != 0) {
      height_value = static_cast<int64_t>(std::stoll(height.c_str()));
    }
    video_output_manager_->SetSize(handle_value, width_value, height_value);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare(
                 "VideoOutputManager.SetAnime4KEnabled") == 0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    auto handle =
        std::get<std::string>(arguments[flutter::EncodableValue("handle")]);
    auto enabled =
        std::get<bool>(arguments[flutter::EncodableValue("enabled")]);
    auto handle_value = static_cast<int64_t>(std::stoll(handle.c_str()));
    video_output_manager_->SetAnime4KEnabled(handle_value, enabled);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare(
                 "VideoOutputManager.SetGPUThreadPriority") == 0) {
    const auto& arguments =
        std::get<flutter::EncodableMap>(*method_call.arguments());
    const auto value = arguments.find(flutter::EncodableValue("priority"));
    int priority = media_kit_video::kDefaultGpuThreadPriority;
    if (value != arguments.end()) {
      if (const auto* int32_value = std::get_if<int32_t>(&value->second)) {
        priority = *int32_value;
      } else if (const auto* int64_value = std::get_if<int64_t>(&value->second)) {
        priority = static_cast<int>(*int64_value);
      }
    }
    video_output_manager_->SetGPUThreadPriority(priority);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare(
                 "VideoOutputManager.SetVideoOutputMode") == 0) {
    const auto& arguments =
        std::get<flutter::EncodableMap>(*method_call.arguments());
    const auto value = arguments.find(flutter::EncodableValue("mode"));
    int mode = static_cast<int>(media_kit_video::kDefaultVideoOutputMode);
    if (value != arguments.end()) {
      if (const auto* int32_value = std::get_if<int32_t>(&value->second)) {
        mode = *int32_value;
      } else if (const auto* int64_value = std::get_if<int64_t>(&value->second)) {
        mode = static_cast<int>(*int64_value);
      }
    }
    video_output_manager_->SetVideoOutputMode(mode);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare(
                 "VideoOutputManager.SetPerformanceMetricsEnabled") == 0) {
    const auto& arguments =
        std::get<flutter::EncodableMap>(*method_call.arguments());
    const auto value = arguments.find(flutter::EncodableValue("enabled"));
    const bool enabled =
        value != arguments.end() && std::get<bool>(value->second);
    PerformanceMetrics::Instance().SetEnabled(enabled);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare(
                 "VideoOutputManager.GetPerformanceMetrics") == 0) {
    UpdateDisplayMetrics(flutter_window_);
    const auto snapshot = PerformanceMetrics::Instance().GetSnapshot();
    const auto configured_mode =
        static_cast<int>(media_kit_video::GetVideoOutputMode());
    std::vector<VideoOutputPerformanceSnapshot> outputs;
    const bool mpv_snapshot_available =
        video_output_manager_->TryGetPerformanceSnapshots(&outputs);
    result->Success(BuildPerformanceMetricsValue(
        snapshot, configured_mode, mpv_snapshot_available, outputs));
  } else if (method_call.method_name().compare(
                 "VideoOutputManager.SetPostProcessingEffect") == 0) {
    auto arguments = std::get<flutter::EncodableMap>(*method_call.arguments());
    auto handle =
        std::get<std::string>(arguments[flutter::EncodableValue("handle")]);
    auto effect =
        std::get<std::string>(arguments[flutter::EncodableValue("effect")]);
    auto enabled =
        std::get<bool>(arguments[flutter::EncodableValue("enabled")]);
    auto handle_value = static_cast<int64_t>(std::stoll(handle.c_str()));

    if (effect.compare("anime4k.restore_cnn_s") == 0) {
      video_output_manager_->SetAnime4KEnabled(handle_value, enabled);
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Success(flutter::EncodableValue(false));
    }
  } else if (method_call.method_name().compare("Utils.EnterNativeFullscreen") ==
             0) {
    auto window =
        ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
    Utils::EnterNativeFullscreen(window);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("Utils.ExitNativeFullscreen") ==
             0) {
    auto window =
        ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
    Utils::ExitNativeFullscreen(window);
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else {
    result->NotImplemented();
  }
}

}  // namespace media_kit_video

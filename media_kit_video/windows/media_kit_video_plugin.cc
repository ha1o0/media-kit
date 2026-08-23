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
#include "video_output_mode.h"

#include <Windows.h>
#include <dxgi.h>
#include <wrl/client.h>

#include <string>

namespace media_kit_video {
namespace {

UINT RegisterPluginMessage(const wchar_t* name, UINT fallback) {
  const UINT message = ::RegisterWindowMessageW(name);
  return message != 0 ? message : fallback;
}

const UINT kMainThreadTaskMessage =
    RegisterPluginMessage(L"media_kit_video.MainThreadTask", WM_APP + 0x6A1);
const UINT kNativeWindowSyncMessage =
    RegisterPluginMessage(L"media_kit_video.NativeWindowSync", WM_APP + 0x6A2);

std::string Utf8FromWide(const wchar_t* value) {
  if (!value || value[0] == L'\0') return std::string();
  const std::wstring wide(value);
  const int input_length = static_cast<int>(wide.size());
  const int length = ::WideCharToMultiByte(
      CP_UTF8, 0, wide.data(), input_length, nullptr, 0, nullptr, nullptr);
  if (length <= 0) return std::string();
  std::string result(static_cast<size_t>(length), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide.data(), input_length, result.data(),
                        length, nullptr, nullptr);
  return result;
}

flutter::EncodableMap AdapterDiagnostics(IDXGIAdapter* adapter) {
  flutter::EncodableMap result;
  if (!adapter) return result;
  DXGI_ADAPTER_DESC description{};
  if (FAILED(adapter->GetDesc(&description))) return result;
  result[flutter::EncodableValue("description")] =
      flutter::EncodableValue(Utf8FromWide(description.Description));
  result[flutter::EncodableValue("vendorId")] = flutter::EncodableValue(
      static_cast<int64_t>(description.VendorId));
  result[flutter::EncodableValue("deviceId")] = flutter::EncodableValue(
      static_cast<int64_t>(description.DeviceId));
  result[flutter::EncodableValue("dedicatedVideoMemory")] =
      flutter::EncodableValue(
          static_cast<int64_t>(description.DedicatedVideoMemory));
  result[flutter::EncodableValue("sharedSystemMemory")] =
      flutter::EncodableValue(
          static_cast<int64_t>(description.SharedSystemMemory));
  result[flutter::EncodableValue("luidHigh")] = flutter::EncodableValue(
      static_cast<int64_t>(description.AdapterLuid.HighPart));
  result[flutter::EncodableValue("luidLow")] = flutter::EncodableValue(
      static_cast<int64_t>(description.AdapterLuid.LowPart));
  return result;
}

flutter::EncodableMap CollectGraphicsDiagnostics(
    flutter::PluginRegistrarWindows* registrar) {
  flutter::EncodableMap result;
  IDXGIAdapter* flutter_adapter = nullptr;
  if (registrar) {
    if (auto* view = registrar->GetView()) {
      flutter_adapter = view->GetGraphicsAdapter();
    }
  }
  result[flutter::EncodableValue("flutterAdapter")] =
      flutter::EncodableValue(AdapterDiagnostics(flutter_adapter));

  flutter::EncodableList adapters;
  Microsoft::WRL::ComPtr<IDXGIFactory1> factory;
  if (SUCCEEDED(::CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) {
    for (UINT index = 0;; index++) {
      Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter;
      const HRESULT enumerate_result = factory->EnumAdapters1(index, &adapter);
      if (enumerate_result == DXGI_ERROR_NOT_FOUND) break;
      if (FAILED(enumerate_result)) break;
      auto diagnostics = AdapterDiagnostics(adapter.Get());
      diagnostics[flutter::EncodableValue("index")] =
          flutter::EncodableValue(static_cast<int64_t>(index));
      adapters.emplace_back(std::move(diagnostics));
    }
  }
  result[flutter::EncodableValue("adapters")] =
      flutter::EncodableValue(std::move(adapters));
  return result;
}

}  // namespace

void MediaKitVideoPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<MediaKitVideoPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

MediaKitVideoPlugin::MediaKitVideoPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar),
      native_video_window_manager_(
          std::make_unique<NativeVideoWindowManager>(registrar)),
      video_output_manager_(std::make_unique<VideoOutputManager>(registrar)) {
  RefreshFlutterWindow();
  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "com.alexmercerind/media_kit_video",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([&](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

MediaKitVideoPlugin::~MediaKitVideoPlugin() {
  if (registrar_ && window_proc_id_ >= 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  }
}

void MediaKitVideoPlugin::RunOnMainThread(std::function<void()> task) {
  RefreshFlutterWindow();
  if (!flutter_window_) {
    return;
  }

  {
    std::lock_guard<std::mutex> lock(main_thread_tasks_mutex_);
    main_thread_tasks_.push(std::move(task));
  }

  ::PostMessage(flutter_window_, kMainThreadTaskMessage, 0, 0);
}

void MediaKitVideoPlugin::RefreshFlutterWindow() {
  const auto view = registrar_ ? registrar_->GetView() : nullptr;
  const HWND view_window = view ? view->GetNativeWindow() : nullptr;
  const HWND root = view_window ? ::GetAncestor(view_window, GA_ROOT) : nullptr;
  if (root) flutter_window_ = root;
}

std::optional<LRESULT> MediaKitVideoPlugin::HandleWindowProc(
    HWND hwnd,
    UINT message,
    WPARAM wparam,
    LPARAM lparam) {
  if (message == kMainThreadTaskMessage) {
    ProcessMainThreadTasks();
    return LRESULT{0};
  }

  if (message == kNativeWindowSyncMessage) {
    native_window_sync_pending_ = false;
    if (native_video_window_manager_) {
      native_video_window_manager_->SyncAll();
    }
    return LRESULT{0};
  }

  if (!native_video_window_manager_ ||
      !native_video_window_manager_->HasWindows()) {
    return std::nullopt;
  }

  if (message == WM_WINDOWPOSCHANGING && lparam) {
    native_video_window_manager_->SyncAllForHostWindowPos(
        *reinterpret_cast<WINDOWPOS*>(lparam));
  }

  switch (message) {
    case WM_ACTIVATE:
    case WM_DPICHANGED:
    case WM_EXITSIZEMOVE:
    case WM_MOVE:
    case WM_SHOWWINDOW:
    case WM_SIZE:
    case WM_WINDOWPOSCHANGED:
      // The runner updates its Flutter child view after plugin delegates have
      // returned. Defer the final repair so resize and fullscreen transitions
      // use the settled client bounds.
      ScheduleNativeWindowSync();
      break;
  }
  return std::nullopt;
}

void MediaKitVideoPlugin::ScheduleNativeWindowSync() {
  RefreshFlutterWindow();
  if (!flutter_window_ || native_window_sync_pending_) return;
  native_window_sync_pending_ = true;
  if (!::PostMessage(flutter_window_, kNativeWindowSyncMessage, 0, 0)) {
    native_window_sync_pending_ = false;
  }
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
  if (method_call.method_name().compare("NativeVideoWindow.Create") == 0) {
    const auto& arguments =
        std::get<flutter::EncodableMap>(*method_call.arguments());
    const auto handle = std::get<std::string>(
        arguments.at(flutter::EncodableValue("handle")));
    const int64_t handle_value = std::stoll(handle);
    bool video_above_flutter = false;
    const auto above_it =
        arguments.find(flutter::EncodableValue("videoAboveFlutter"));
    if (above_it != arguments.end() &&
        std::holds_alternative<bool>(above_it->second)) {
      video_above_flutter = std::get<bool>(above_it->second);
    }
    const HWND window = native_video_window_manager_->Create(
        handle_value, video_above_flutter);
    result->Success(flutter::EncodableValue(
        static_cast<int64_t>(reinterpret_cast<intptr_t>(window))));
  } else if (method_call.method_name().compare(
                 "NativeVideoWindow.GetDiagnostics") == 0) {
    result->Success(flutter::EncodableValue(
        CollectGraphicsDiagnostics(registrar_)));
  } else if (method_call.method_name().compare(
                 "NativeVideoWindow.HideAll") == 0) {
    native_video_window_manager_->HideAll();
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare(
                 "NativeVideoWindow.SetBounds") == 0) {
    const auto& arguments =
        std::get<flutter::EncodableMap>(*method_call.arguments());
    const auto handle = std::get<std::string>(
        arguments.at(flutter::EncodableValue("handle")));
    const int status = native_video_window_manager_->SetBounds(
        std::stoll(handle),
        std::get<double>(arguments.at(flutter::EncodableValue("x"))),
        std::get<double>(arguments.at(flutter::EncodableValue("y"))),
        std::get<double>(arguments.at(flutter::EncodableValue("width"))),
        std::get<double>(arguments.at(flutter::EncodableValue("height"))),
        std::get<bool>(arguments.at(flutter::EncodableValue("visible"))));
    result->Success(flutter::EncodableValue(status));
  } else if (method_call.method_name().compare("NativeVideoWindow.Dispose") ==
             0) {
    const auto& arguments =
        std::get<flutter::EncodableMap>(*method_call.arguments());
    const auto handle = std::get<std::string>(
        arguments.at(flutter::EncodableValue("handle")));
    native_video_window_manager_->Dispose(std::stoll(handle));
    result->Success(flutter::EncodableValue(std::monostate{}));
  } else if (method_call.method_name().compare("VideoOutputManager.Create") ==
             0) {
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

// This file is a part of media_kit.

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "native_video_window_manager.h"

#include <algorithm>
#include <cmath>
#include <dwmapi.h>

namespace media_kit_video {
namespace {

constexpr wchar_t kNativeVideoWindowClass[] =
    L"MEDIA_KIT_NATIVE_VIDEO_WINDOW";
constexpr UINT_PTR kNativeVideoResyncTimer = 1;
constexpr UINT kNativeVideoResyncIntervalMs = 250;
// Window effects and gpu-next may finish reconfiguring several seconds after
// the first frame. Keep the low-frequency guard alive only during startup.
constexpr ULONGLONG kNativeVideoResyncDurationMs = 10000;
// Use numeric values so the plugin still builds with Windows SDKs older than
// 10.0.22000.0. Unsupported systems simply ignore the DWM attribute.
constexpr auto kDwmWindowCornerPreference =
    static_cast<DWMWINDOWATTRIBUTE>(33);
constexpr int kDwmDoNotRound = 1;
constexpr int kDwmRound = 2;

NativeVideoWindowManager* g_native_video_window_manager = nullptr;

double ScaleForWindow(HWND window) {
  using GetDpiForWindowProc = UINT(WINAPI*)(HWND);
  const auto user32 = ::GetModuleHandleW(L"user32.dll");
  const auto get_dpi_for_window = user32
                                      ? reinterpret_cast<GetDpiForWindowProc>(
                                            ::GetProcAddress(
                                                user32, "GetDpiForWindow"))
                                      : nullptr;
  const UINT dpi = get_dpi_for_window ? get_dpi_for_window(window) : 96;
  return std::max(1U, dpi) / 96.0;
}

bool CoversMonitor(HWND window) {
  RECT window_rect{};
  if (!window || !::GetWindowRect(window, &window_rect)) return false;

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  const HMONITOR monitor =
      ::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  if (!monitor || !::GetMonitorInfoW(monitor, &monitor_info)) return false;

  const RECT& monitor_rect = monitor_info.rcMonitor;
  return window_rect.left <= monitor_rect.left &&
         window_rect.top <= monitor_rect.top &&
         window_rect.right >= monitor_rect.right &&
         window_rect.bottom >= monitor_rect.bottom;
}

bool IsArranged(HWND window) {
  using IsWindowArrangedProc = BOOL(WINAPI*)(HWND);
  static const IsWindowArrangedProc is_window_arranged = [] {
    const auto user32 = ::GetModuleHandleW(L"user32.dll");
    return user32 ? reinterpret_cast<IsWindowArrangedProc>(
                        ::GetProcAddress(user32, "IsWindowArranged"))
                  : nullptr;
  }();
  return is_window_arranged && is_window_arranged(window);
}

}  // namespace

NativeVideoWindowManager::NativeVideoWindowManager(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  g_native_video_window_manager = this;
  RefreshFlutterWindow();
}

NativeVideoWindowManager::~NativeVideoWindowManager() {
  for (auto& item : entries_) {
    if (item.second.window) {
      ::KillTimer(item.second.window, kNativeVideoResyncTimer);
      ::DestroyWindow(item.second.window);
    }
  }
  entries_.clear();
  if (g_native_video_window_manager == this) {
    g_native_video_window_manager = nullptr;
  }
  if (owns_window_class_) {
    ::UnregisterClassW(kNativeVideoWindowClass, ::GetModuleHandleW(nullptr));
  }
}

bool NativeVideoWindowManager::EnsureWindowClass() {
  WNDCLASSEXW existing{};
  existing.cbSize = sizeof(existing);
  if (::GetClassInfoExW(::GetModuleHandleW(nullptr),
                        kNativeVideoWindowClass, &existing)) {
    return true;
  }

  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.style = CS_OWNDC;
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = ::GetModuleHandleW(nullptr);
  window_class.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground =
      reinterpret_cast<HBRUSH>(::GetStockObject(BLACK_BRUSH));
  window_class.lpszClassName = kNativeVideoWindowClass;
  owns_window_class_ = ::RegisterClassExW(&window_class) != 0;
  return owns_window_class_;
}

HWND NativeVideoWindowManager::Create(int64_t handle,
                                      bool video_above_flutter) {
  const auto existing = entries_.find(handle);
  if (existing != entries_.end()) return existing->second.window;
  RefreshFlutterWindow();
  if (!flutter_window_ || !EnsureWindowClass()) return nullptr;

  const HWND window = ::CreateWindowExW(
      WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kNativeVideoWindowClass, L"",
      WS_POPUP | WS_VISIBLE | WS_CLIPSIBLINGS | WS_CLIPCHILDREN,
      0, 0, 1, 1, nullptr, nullptr, ::GetModuleHandleW(nullptr), nullptr);
  if (!window) return nullptr;

  Entry entry{};
  entry.window = window;
  entry.visible = !shutdown_hidden_;
  entry.video_above_flutter = video_above_flutter;
  RECT client{};
  if (flutter_window_ && ::GetClientRect(flutter_window_, &client)) {
    entry.width = std::max(1L, client.right - client.left) /
                  ScaleForWindow(flutter_window_);
    entry.height = std::max(1L, client.bottom - client.top) /
                   ScaleForWindow(flutter_window_);
  } else {
    entry.width = 1.0;
    entry.height = 1.0;
  }
  entries_.emplace(handle, entry);
  // mpv may resize the embedding HWND while initializing gpu-next. Start the
  // native repair loop immediately, even if Flutter has not laid out its
  // Video widget yet and has not sent SetBounds.
  ScheduleResync(entries_.at(handle));
  Sync(entries_.at(handle));
  ::InvalidateRect(window, nullptr, TRUE);
  ::UpdateWindow(window);
  return window;
}

void NativeVideoWindowManager::ScheduleResync(Entry& entry) {
  if (!entry.window || !entry.visible) return;
  entry.resync_deadline =
      ::GetTickCount64() + kNativeVideoResyncDurationMs;
  ::SetTimer(entry.window, kNativeVideoResyncTimer,
             kNativeVideoResyncIntervalMs, nullptr);
}

void NativeVideoWindowManager::RefreshFlutterWindow() {
  const auto view = registrar_ ? registrar_->GetView() : nullptr;
  const HWND view_window = view ? view->GetNativeWindow() : nullptr;
  const HWND root = view_window ? ::GetAncestor(view_window, GA_ROOT) : nullptr;
  if (root) flutter_window_ = root;
}

void NativeVideoWindowManager::UpdateCornerPreference(Entry& entry) {
  if (!entry.window || !flutter_window_) return;

  // The native video HWND is an independent WS_POPUP, so it does not inherit
  // the rounded DWM clip of the transparent Flutter host. Match the host while
  // windowed, but keep arranged, maximized, and fullscreen playback flush to
  // the screen.
  const bool suppress_rounding =
      IsArranged(flutter_window_) || ::IsZoomed(flutter_window_) ||
      CoversMonitor(flutter_window_);
  const int preference = suppress_rounding ? kDwmDoNotRound : kDwmRound;
  if (entry.corner_preference == preference) return;

  ::DwmSetWindowAttribute(entry.window, kDwmWindowCornerPreference,
                          &preference, sizeof(preference));
  // Cache attempted values too. Older Windows versions reject attribute 33;
  // retry only if the host state changes instead of on every bounds sync.
  entry.corner_preference = preference;
}

int NativeVideoWindowManager::SetBounds(int64_t handle,
                                        double x,
                                        double y,
                                        double width,
                                        double height,
                                        bool visible) {
  const auto item = entries_.find(handle);
  if (item == entries_.end()) return 0;
  auto& entry = item->second;
  entry.x = x;
  entry.y = y;
  entry.width = width;
  entry.height = height;
  entry.visible = visible && !shutdown_hidden_;
  if (entry.visible) {
    ScheduleResync(entry);
  } else {
    entry.resync_deadline = 0;
    ::KillTimer(entry.window, kNativeVideoResyncTimer);
  }
  return Sync(entry);
}

void NativeVideoWindowManager::Dispose(int64_t handle) {
  const auto item = entries_.find(handle);
  if (item == entries_.end()) return;
  if (item->second.window) {
    ::KillTimer(item->second.window, kNativeVideoResyncTimer);
    ::DestroyWindow(item->second.window);
  }
  entries_.erase(item);
}

void NativeVideoWindowManager::HideAll() {
  shutdown_hidden_ = true;
  for (auto& item : entries_) {
    auto& entry = item.second;
    entry.visible = false;
    entry.resync_deadline = 0;
    if (entry.window) {
      ::KillTimer(entry.window, kNativeVideoResyncTimer);
      ::ShowWindow(entry.window, SW_HIDE);
    }
  }
}

void NativeVideoWindowManager::SyncAll() {
  for (auto& item : entries_) {
    Sync(item.second);
  }
}

void NativeVideoWindowManager::SyncAllForHostWindowPos(
    const WINDOWPOS& window_pos) {
  if ((window_pos.flags & SWP_NOMOVE) != 0) return;
  RefreshFlutterWindow();
  if (!flutter_window_) return;

  RECT current_host{};
  if (!::GetWindowRect(flutter_window_, &current_host)) return;
  const int delta_x = window_pos.x - current_host.left;
  const int delta_y = window_pos.y - current_host.top;
  if (delta_x == 0 && delta_y == 0) return;

  for (auto& item : entries_) {
    auto& entry = item.second;
    if (!entry.window || !entry.visible || entry.syncing) continue;
    RECT current_video{};
    if (!::GetWindowRect(entry.window, &current_video)) continue;

    entry.syncing = true;
    ::SetWindowPos(
        entry.window, nullptr, current_video.left + delta_x,
        current_video.top + delta_y, current_video.right - current_video.left,
        current_video.bottom - current_video.top,
        SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOZORDER | SWP_SHOWWINDOW);
    entry.syncing = false;
  }
}

int NativeVideoWindowManager::Sync(Entry& entry) {
  if (entry.syncing) return 0;
  entry.syncing = true;
  const auto finish = [&entry](int result) {
    entry.syncing = false;
    return result;
  };
  if (entry.resync_deadline != 0 &&
      ::GetTickCount64() >= entry.resync_deadline) {
    entry.resync_deadline = 0;
    if (entry.window) {
      ::KillTimer(entry.window, kNativeVideoResyncTimer);
    }
  }
  const auto view = registrar_ ? registrar_->GetView() : nullptr;
  RefreshFlutterWindow();
  UpdateCornerPreference(entry);
  const HWND flutter_view = view ? view->GetNativeWindow() : nullptr;
  int status = 1;
  if (entry.visible) status |= 1 << 1;
  if (entry.window) status |= 1 << 2;
  if (flutter_view) status |= 1 << 3;
  if (flutter_window_) status |= 1 << 4;
  if (flutter_window_ && ::IsWindowVisible(flutter_window_)) status |= 1 << 5;
  if (flutter_window_ && !::IsIconic(flutter_window_)) status |= 1 << 6;
  if (entry.width > 0.0 && entry.height > 0.0) status |= 1 << 7;
  const bool can_show = entry.visible && entry.window && flutter_view &&
                        flutter_window_ && ::IsWindowVisible(flutter_window_) &&
                        !::IsIconic(flutter_window_) && entry.width > 0.0 &&
                        entry.height > 0.0;
  if (!can_show) {
    if (entry.window) ::ShowWindow(entry.window, SW_HIDE);
    return finish(status);
  }

  POINT view_origin{0, 0};
  if (!::ClientToScreen(flutter_view, &view_origin)) {
    ::ShowWindow(entry.window, SW_HIDE);
    return finish(status);
  }
  status |= 1 << 8;

  const double scale = ScaleForWindow(flutter_window_);
  const int x = view_origin.x + static_cast<int>(std::lround(entry.x * scale));
  const int y = view_origin.y + static_cast<int>(std::lround(entry.y * scale));
  const int width =
      std::max(1, static_cast<int>(std::lround(entry.width * scale)));
  const int height =
      std::max(1, static_cast<int>(std::lround(entry.height * scale)));

  // The production path inserts after Flutter so controls remain above the
  // video. The opt-in diagnostic path puts video at the top of the non-topmost
  // band, fully occluding Flutter over the video area and isolating DWM overlay
  // composition without hiding the host (Alt+F4 and window lifecycle remain).
  const HWND insert_after =
      entry.video_above_flutter ? HWND_TOP : flutter_window_;
  if (::SetWindowPos(entry.window, insert_after, x, y, width, height,
                     SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW)) {
    status |= 1 << 9;
  }
  return finish(status);
}

LRESULT CALLBACK NativeVideoWindowManager::WindowProc(HWND window,
                                                       UINT message,
                                                       WPARAM wparam,
                                                       LPARAM lparam) {
  if (message == WM_WINDOWPOSCHANGING && lparam) {
    auto* position = reinterpret_cast<WINDOWPOS*>(lparam);
    if ((position->flags & SWP_NOSIZE) == 0) {
      // Do not let DWM preserve and stretch the previous client image while
      // mpv is resizing its swap chain. gpu-next will present a correctly
      // fitted replacement frame immediately after WM_SIZE.
      position->flags |= SWP_NOCOPYBITS;
    }
  }
  if (message == WM_SIZE) {
    ::InvalidateRect(window, nullptr, FALSE);
  }
  if (message == WM_TIMER && wparam == kNativeVideoResyncTimer) {
    auto* manager = g_native_video_window_manager;
    if (manager) {
      for (auto& item : manager->entries_) {
        if (item.second.window == window) {
          manager->Sync(item.second);
          break;
        }
      }
    }
    return 0;
  }
  if (message == WM_SHOWWINDOW && wparam == FALSE) {
    auto* manager = g_native_video_window_manager;
    if (manager) {
      for (auto& item : manager->entries_) {
        if (item.second.window == window) {
          // mpv may hide the embedding target while its VO is reconfigured.
          // Re-apply the latest bounds while the Flutter host remains visible.
          if (item.second.visible && manager->flutter_window_ &&
              ::IsWindowVisible(manager->flutter_window_) &&
              !::IsIconic(manager->flutter_window_)) {
            manager->Sync(item.second);
          }
          break;
        }
      }
    }
  }
  if (message == WM_WINDOWPOSCHANGED) {
    auto* manager = g_native_video_window_manager;
    if (manager) {
      for (auto& item : manager->entries_) {
        if (item.second.window == window) {
          if (item.second.visible && !item.second.syncing) {
            manager->Sync(item.second);
          }
          break;
        }
      }
    }
  }
  if (message == WM_ERASEBKGND) {
    RECT client{};
    if (::GetClientRect(window, &client)) {
      ::FillRect(reinterpret_cast<HDC>(wparam), &client,
                 reinterpret_cast<HBRUSH>(::GetStockObject(BLACK_BRUSH)));
    }
    return 1;
  }
  if (message == WM_NCHITTEST) return HTTRANSPARENT;
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  return ::DefWindowProcW(window, message, wparam, lparam);
}

}  // namespace media_kit_video

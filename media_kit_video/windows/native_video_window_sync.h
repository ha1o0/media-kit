// This file is a part of media_kit.
#ifndef MEDIA_KIT_NATIVE_VIDEO_WINDOW_SYNC_H_
#define MEDIA_KIT_NATIVE_VIDEO_WINDOW_SYNC_H_

#include <Windows.h>

namespace media_kit_video {

// Query the real HWND state, not just the last requested bounds: mpv, Windows
// Snap and host activation may independently change geometry or stacking.
inline bool NativeVideoWindowHasZOrder(HWND window, HWND insert_after) {
  const HWND previous = ::GetWindow(window, GW_HWNDPREV);
  const bool topmost =
      (::GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
  if (insert_after == HWND_TOP) {
    // HWND_TOP moves to the top of the window's current z-order band.
    return !previous ||
           (!topmost &&
            (::GetWindowLongPtrW(previous, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0);
  }
  // An explicit predecessor does not itself change WS_EX_TOPMOST. Preserve
  // the existing SetWindowPos semantics, including a topmost host followed by
  // a non-topmost video window at the start of the next band.
  return previous == insert_after;
}

inline bool SyncNativeVideoWindow(HWND window, HWND insert_after,
                                  int x, int y, int width, int height) {
  RECT current{};
  const bool has_bounds = ::GetWindowRect(window, &current) != FALSE;
  const bool move = !has_bounds || current.left != x || current.top != y;
  const bool resize = !has_bounds || current.right - current.left != width ||
                      current.bottom - current.top != height;
  const bool reorder = !NativeVideoWindowHasZOrder(window, insert_after);
  const bool show = !::IsWindowVisible(window);
  if (!move && !resize && !reorder && !show) return true;

  UINT flags = SWP_NOACTIVATE | SWP_NOOWNERZORDER;
  if (!move) flags |= SWP_NOMOVE;
  if (!resize) flags |= SWP_NOSIZE;
  if (!reorder) flags |= SWP_NOZORDER;
  if (show) flags |= SWP_SHOWWINDOW;
  if (resize) flags |= SWP_NOCOPYBITS;
  return ::SetWindowPos(window, insert_after, x, y, width, height, flags) != FALSE;
}

inline void HideNativeVideoWindow(HWND window) {
  if (window && ::IsWindowVisible(window)) ::ShowWindow(window, SW_HIDE);
}

}  // namespace media_kit_video
#endif  // MEDIA_KIT_NATIVE_VIDEO_WINDOW_SYNC_H_

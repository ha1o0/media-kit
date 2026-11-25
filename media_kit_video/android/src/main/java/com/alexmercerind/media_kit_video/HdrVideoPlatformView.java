package com.alexmercerind.media_kit_video;

import android.content.Context;
import android.view.SurfaceHolder;
import android.hardware.display.DisplayManager;
import android.os.Handler;
import android.os.Looper;
import android.view.SurfaceView;
import android.view.View;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.widget.FrameLayout;
import java.util.Map;
import androidx.annotation.NonNull;
import io.flutter.plugin.platform.PlatformView;

/** Direct compositor surface. mpv still renders video, ASS and bitmap subtitles. */
final class HdrVideoPlatformView implements PlatformView, SurfaceHolder.Callback, DisplayManager.DisplayListener {
    final SurfaceView view;
    private final SurfaceView subtitles;
    private final FrameLayout container;
    private double x, y, width = 1, height = 1;
    private int rotation;
    private boolean mirror;
    private final Runnable onDispose;
    final boolean fullscreen;
    private final VideoOutput output;
    private final DisplayManager displays;
    private boolean available;
    private boolean disposed;

    HdrVideoPlatformView(Context context, VideoOutput output, boolean fullscreen, Map<?, ?> layout, Runnable onDispose) {
        this.output = output;
        this.onDispose = onDispose;
        this.fullscreen = fullscreen;
        displays = (DisplayManager) context.getSystemService(Context.DISPLAY_SERVICE);
        view = new SurfaceView(context) {
            @Override protected void onWindowVisibilityChanged(int visibility) {
                super.onWindowVisibilityChanged(visibility);
                changed();
            }
        };
        container = new FrameLayout(context);
        container.setBackgroundColor(Color.BLACK);
        container.setClipChildren(true);
        container.setClipToPadding(true);
        container.setFocusable(false);
        container.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        container.addView(view, new FrameLayout.LayoutParams(1, 1));
        subtitles = new SurfaceView(context);
        subtitles.setZOrderMediaOverlay(true);
        subtitles.getHolder().setFormat(PixelFormat.TRANSLUCENT);
        subtitles.setFocusable(false);
        subtitles.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        container.addView(subtitles, new FrameLayout.LayoutParams(1, 1));
        subtitles.getHolder().addCallback(new SurfaceHolder.Callback() {
            @Override public void surfaceCreated(@NonNull SurfaceHolder holder) {
                // GPU-rendered playback also owns this view. Publish a clear
                // first buffer so an unused subtitle plane cannot cover it.
                android.graphics.Canvas canvas = null;
                try {
                    canvas = holder.lockCanvas();
                    if (canvas != null) canvas.drawColor(Color.TRANSPARENT,
                            android.graphics.PorterDuff.Mode.CLEAR);
                } catch (IllegalArgumentException | IllegalStateException unavailable) {
                    // A view may already be detaching during the callback.
                } finally {
                    if (canvas != null) holder.unlockCanvasAndPost(canvas);
                }
                changed();
            }
            @Override public void surfaceChanged(@NonNull SurfaceHolder holder, int format, int w, int h) { changed(); }
            @Override public void surfaceDestroyed(@NonNull SurfaceHolder holder) { changed(); }
        });
        container.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> layoutVideo());
        updateLayout(layout);
        view.setFocusable(false);
        view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        view.getHolder().addCallback(this);
        view.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override public void onViewAttachedToWindow(View v) { changed(); }
            @Override public void onViewDetachedFromWindow(View v) { changed(); }
        });
        view.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> changed());
        output.attach(this);
        if (displays != null) displays.registerDisplayListener(this, new Handler(Looper.getMainLooper()));
    }

    boolean eligible() {
        // Flutter temporarily hides the mutator parent while synchronizing
        // overlay frames. That is not a decoder/surface handoff: switching VO
        // there would invalidate the very frame Flutter is waiting to display.
        return !disposed && available && view.isAttachedToWindow()
                && view.getWindowVisibility() == View.VISIBLE
                && view.getWidth() > 0 && view.getHeight() > 0
                && view.getHolder().getSurface().isValid();
    }

    android.view.Surface subtitleSurface() {
        final android.view.Surface surface = subtitles.getHolder().getSurface();
        return surface != null && surface.isValid() ? surface : null;
    }

    private void changed() { if (!disposed) output.selectNativeSurface(); }
    @Override public View getView() { return container; }

    void updateLayout(Map<?, ?> layout) {
        x = number(layout, "x", 0);
        y = number(layout, "y", 0);
        width = number(layout, "width", 1);
        height = number(layout, "height", 1);
        rotation = (int) number(layout, "rotation", 0);
        mirror = Boolean.TRUE.equals(layout.get("mirror"));
        layoutVideo();
    }

    private static double number(Map<?, ?> map, String key, double fallback) {
        Object value = map.get(key);
        double number = value instanceof Number ? ((Number) value).doubleValue() : fallback;
        return Double.isFinite(number) ? number : fallback;
    }

    private void layoutVideo() {
        int cw = container.getWidth(), ch = container.getHeight();
        if (cw <= 0 || ch <= 0) return;
        int w = Math.max(1, (int) Math.round(width * cw));
        int h = Math.max(1, (int) Math.round(height * ch));
        boolean quarterTurn = rotation == 90 || rotation == 270;
        int vw = quarterTurn ? h : w, vh = quarterTurn ? w : h;
        int left = (int) Math.round(x * cw + (w - vw) * .5);
        int top = (int) Math.round(y * ch + (h - vh) * .5);
        FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) view.getLayoutParams();
        if (params.width != vw || params.height != vh || params.leftMargin != left || params.topMargin != top) {
            params.width = vw; params.height = vh;
            params.leftMargin = left; params.topMargin = top;
            view.setLayoutParams(params);
        }
        view.setRotation(rotation);
        view.setScaleX(mirror ? -1 : 1);
        FrameLayout.LayoutParams subtitleLayout = (FrameLayout.LayoutParams) subtitles.getLayoutParams();
        if (subtitleLayout.width != vw || subtitleLayout.height != vh
                || subtitleLayout.leftMargin != left || subtitleLayout.topMargin != top) {
            subtitles.setLayoutParams(new FrameLayout.LayoutParams(params));
        }
        subtitles.setRotation(rotation);
        subtitles.setScaleX(mirror ? -1 : 1);
    }
    @Override public void surfaceCreated(@NonNull SurfaceHolder holder) {
        available = true;
        changed();
    }
    @Override public void surfaceChanged(@NonNull SurfaceHolder holder, int format, int w, int h) {
        available = true;
        changed();
    }
    @Override public void surfaceDestroyed(@NonNull SurfaceHolder holder) {
        available = false;
        changed();
    }
    @Override public void onDisplayAdded(int id) { changed(); }
    @Override public void onDisplayRemoved(int id) { changed(); }
    @Override public void onDisplayChanged(int id) { changed(); }

    @Override public void dispose() {
        disposed = true;
        if (displays != null) displays.unregisterDisplayListener(this);
        available = false;
        view.getHolder().removeCallback(this);
        output.detach(this);
        onDispose.run();
    }
}

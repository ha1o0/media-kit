package com.alexmercerind.media_kit_video;

import android.graphics.Bitmap;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.view.PixelCopy;
import android.view.Surface;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Small pre-blurred copies of the surface mpv renders to, for Flutter panels
 * that sit above the video. Flutter cannot sample a native SurfaceView, and a
 * per-frame backdrop filter over a video texture costs a full blur every
 * frame. A bounded copy a few times per second costs one scaled read on the
 * render thread and a few kilobytes on this thread, only while a panel asks.
 *
 * Copy failures are silent: the consumer keeps its opaque fallback.
 */
final class VideoBackdropSampler {
    interface Sink {
        /**
         * Called on the main thread. The direct buffer starts with
         * {@link #HEADER_BYTES} reserved for the receiver, followed by tightly
         * packed opaque RGBA rows, and is positioned at its end.
         */
        void onBackdrop(int width, int height, ByteBuffer message);
    }

    static final int HEADER_BYTES = 16;

    /** Long edge read from the surface, and the factor it is reduced by. */
    private static final int COPY_LONG_EDGE = 384;
    private static final int REDUCTION = 4;
    private static final long INTERVAL_MS = 80;
    private static final long IDLE_INTERVAL_MS = 400;
    private static final long FAILURE_INTERVAL_MS = 1000;

    private final Handler main = new Handler(Looper.getMainLooper());
    private final Sink sink;
    private HandlerThread thread;
    private Handler worker;

    // Guarded by this.
    private Surface surface;
    private int sourceWidth, sourceHeight;
    private boolean enabled;
    private boolean disposed;
    private int generation;

    // Worker thread only.
    private Bitmap copy;
    private int[] pixels;
    private int[] channels, scratch;
    private int lastHash;
    private boolean hasLast;
    private int unchanged;

    VideoBackdropSampler(Sink sink) {
        this.sink = sink;
    }

    synchronized void setSource(Surface surface, int width, int height) {
        if (this.surface == surface && sourceWidth == width && sourceHeight == height) return;
        this.surface = surface;
        sourceWidth = width;
        sourceHeight = height;
        restart();
    }

    synchronized void setEnabled(boolean enabled) {
        if (this.enabled == enabled || disposed) return;
        this.enabled = enabled;
        restart();
    }

    synchronized void dispose() {
        disposed = true;
        enabled = false;
        surface = null;
        generation++;
        if (thread != null) {
            thread.quitSafely();
            thread = null;
            worker = null;
        }
    }

    private void restart() {
        final int current = ++generation;
        if (!enabled || disposed || Build.VERSION.SDK_INT < 24) return;
        if (thread == null) {
            thread = new HandlerThread("media_kit_video.backdrop");
            thread.start();
            worker = new Handler(thread.getLooper());
        }
        worker.post(() -> {
            hasLast = false;
            unchanged = 0;
            capture(current);
        });
    }

    private void schedule(int current, long delay) {
        final Handler handler;
        synchronized (this) {
            if (current != generation || !enabled || disposed) return;
            handler = worker;
        }
        if (handler != null) handler.postDelayed(() -> capture(current), delay);
    }

    private void capture(int current) {
        final Surface source;
        final int width, height;
        final Handler handler;
        synchronized (this) {
            if (current != generation || !enabled || disposed) return;
            source = surface;
            width = sourceWidth;
            height = sourceHeight;
            handler = worker;
        }
        if (source == null || handler == null || width < 2 || height < 2 || !source.isValid()) {
            schedule(current, FAILURE_INTERVAL_MS);
            return;
        }
        final double scale = (double) COPY_LONG_EDGE / Math.max(width, height);
        final int outWidth = Math.max(2, (int) Math.round(width * scale / REDUCTION));
        final int outHeight = Math.max(2, (int) Math.round(height * scale / REDUCTION));
        final int copyWidth = outWidth * REDUCTION, copyHeight = outHeight * REDUCTION;
        if (copy == null || copy.getWidth() != copyWidth || copy.getHeight() != copyHeight) {
            copy = Bitmap.createBitmap(copyWidth, copyHeight, Bitmap.Config.ARGB_8888);
            pixels = new int[copyWidth * copyHeight];
            channels = new int[outWidth * outHeight * 3];
            scratch = new int[outWidth * outHeight * 3];
            hasLast = false;
        }
        try {
            PixelCopy.request(source, copy, result -> {
                if (result != PixelCopy.SUCCESS) {
                    schedule(current, FAILURE_INTERVAL_MS);
                    return;
                }
                publish(current, outWidth, outHeight);
            }, handler);
        } catch (IllegalArgumentException | IllegalStateException released) {
            // The surface went away between the validity check and the request.
            schedule(current, FAILURE_INTERVAL_MS);
        }
    }

    private void publish(int current, int width, int height) {
        synchronized (this) {
            if (current != generation || !enabled || disposed) return;
        }
        // A request from before a size change can still complete afterwards.
        if (copy == null || copy.getWidth() != width * REDUCTION
                || copy.getHeight() != height * REDUCTION) return;
        copy.getPixels(pixels, 0, copy.getWidth(), 0, 0, copy.getWidth(), copy.getHeight());
        reduce(pixels, copy.getWidth(), channels, width, height, REDUCTION);
        // Three box passes approximate a Gaussian with sigma about 2.4 pixels,
        // which also band-limits the image for bilinear enlargement.
        for (int pass = 0; pass < 3; pass++) {
            blurRows(channels, scratch, width, height, 2);
            blurColumns(scratch, channels, width, height, 2);
        }
        final ByteBuffer rgba = ByteBuffer.allocateDirect(HEADER_BYTES + width * height * 4)
                .order(ByteOrder.nativeOrder());
        rgba.position(HEADER_BYTES);
        int hash = 17;
        for (int i = 0, n = width * height; i < n; i++) {
            final int r = channels[i * 3], g = channels[i * 3 + 1], b = channels[i * 3 + 2];
            rgba.put((byte) r).put((byte) g).put((byte) b).put((byte) 0xFF);
            hash = 31 * hash + ((r << 16) | (g << 8) | b);
        }
        // A paused or static picture needs neither a new image nor this rate.
        if (hasLast && hash == lastHash) {
            unchanged++;
            schedule(current, unchanged > 3 ? IDLE_INTERVAL_MS : INTERVAL_MS);
            return;
        }
        hasLast = true;
        lastHash = hash;
        unchanged = 0;
        main.post(() -> {
            synchronized (VideoBackdropSampler.this) {
                if (current != generation || !enabled || disposed) return;
            }
            sink.onBackdrop(width, height, rgba);
        });
        schedule(current, INTERVAL_MS);
    }

    /** Area average: every copied pixel contributes, so detail does not alias. */
    static void reduce(int[] argb, int sourceWidth, int[] rgb, int width, int height, int factor) {
        final int samples = factor * factor;
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                int r = 0, g = 0, b = 0;
                for (int dy = 0; dy < factor; dy++) {
                    int row = (y * factor + dy) * sourceWidth + x * factor;
                    for (int dx = 0; dx < factor; dx++) {
                        final int pixel = argb[row + dx];
                        r += (pixel >> 16) & 0xFF;
                        g += (pixel >> 8) & 0xFF;
                        b += pixel & 0xFF;
                    }
                }
                final int out = (y * width + x) * 3;
                rgb[out] = r / samples;
                rgb[out + 1] = g / samples;
                rgb[out + 2] = b / samples;
            }
        }
    }

    static void blurRows(int[] source, int[] target, int width, int height, int radius) {
        final int window = radius * 2 + 1;
        for (int y = 0; y < height; y++) {
            for (int c = 0; c < 3; c++) {
                int sum = 0;
                for (int i = -radius; i <= radius; i++) {
                    sum += source[(y * width + clamp(i, width)) * 3 + c];
                }
                for (int x = 0; x < width; x++) {
                    target[(y * width + x) * 3 + c] = sum / window;
                    sum += source[(y * width + clamp(x + radius + 1, width)) * 3 + c]
                            - source[(y * width + clamp(x - radius, width)) * 3 + c];
                }
            }
        }
    }

    static void blurColumns(int[] source, int[] target, int width, int height, int radius) {
        final int window = radius * 2 + 1;
        for (int x = 0; x < width; x++) {
            for (int c = 0; c < 3; c++) {
                int sum = 0;
                for (int i = -radius; i <= radius; i++) {
                    sum += source[(clamp(i, height) * width + x) * 3 + c];
                }
                for (int y = 0; y < height; y++) {
                    target[(y * width + x) * 3 + c] = sum / window;
                    sum += source[(clamp(y + radius + 1, height) * width + x) * 3 + c]
                            - source[(clamp(y - radius, height) * width + x) * 3 + c];
                }
            }
        }
    }

    private static int clamp(int value, int size) {
        return value < 0 ? 0 : Math.min(value, size - 1);
    }
}

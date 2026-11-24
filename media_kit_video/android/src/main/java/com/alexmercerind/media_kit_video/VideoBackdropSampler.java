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
import java.util.Arrays;

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
         * the handle/dimensions prefix reserved for the receiver and an
         * extended header describing the picture within its blurred black
         * gutter, followed by opaque RGBA rows. Positioned at its end.
         */
        void onBackdrop(int width, int height, ByteBuffer message);
    }

    static final int HEADER_BYTES = 40;
    static final int HEADER_MAGIC = 0x42474432; // BGD2
    static final int HEADER_VERSION = 2;

    /** Long edge read from the surface, and the factor it is reduced by. */
    private static final int COPY_LONG_EDGE = 384;
    private static final int REDUCTION = 4;
    private static final int BLUR_RADIUS = 2;
    private static final int BLUR_PASSES = 3;
    // Include the complete convolution support, so video-to-letterbox blur
    // fades to black instead of being clipped at the picture's edge.
    static final int PADDING = BLUR_RADIUS * BLUR_PASSES;
    private static final int PICTURE_LONG_EDGE = COPY_LONG_EDGE / REDUCTION - 2 * PADDING;
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
    private int[] reduced, channels, scratch;
    private int lastHash;
    private boolean hasLast;
    private int unchanged;
    private boolean hasSuccessfulCopy;
    private int initialNoDataRetries;

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
            hasSuccessfulCopy = false;
            initialNoDataRetries = 0;
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
        // The gutter shares the existing 96px output budget with the picture.
        final double scale = (double) PICTURE_LONG_EDGE / Math.max(width, height);
        final int outWidth = Math.max(2, (int) Math.round(width * scale));
        final int outHeight = Math.max(2, (int) Math.round(height * scale));
        final int copyWidth = outWidth * REDUCTION, copyHeight = outHeight * REDUCTION;
        if (copy == null || copy.getWidth() != copyWidth || copy.getHeight() != copyHeight) {
            copy = Bitmap.createBitmap(copyWidth, copyHeight, Bitmap.Config.ARGB_8888);
            pixels = new int[copyWidth * copyHeight];
            reduced = new int[outWidth * outHeight * 3];
            channels = new int[(outWidth + 2 * PADDING) * (outHeight + 2 * PADDING) * 3];
            scratch = new int[channels.length];
            hasLast = false;
        }
        try {
            PixelCopy.request(source, copy, result -> {
                synchronized (VideoBackdropSampler.this) {
                    if (current != generation || !enabled || disposed) return;
                }
                if (result != PixelCopy.SUCCESS) {
                    final long delay = copyFailureDelay(result, hasSuccessfulCopy, initialNoDataRetries);
                    if (delay == INTERVAL_MS) initialNoDataRetries++;
                    schedule(current, delay);
                    return;
                }
                hasSuccessfulCopy = true;
                publish(current, outWidth, outHeight);
            }, handler);
        } catch (IllegalArgumentException | IllegalStateException released) {
            // The surface went away between the validity check and the request.
            schedule(current, FAILURE_INTERVAL_MS);
        }
    }

    /** A Surface can be valid before its first video frame has arrived. */
    static long copyFailureDelay(int result, boolean hasSuccessfulCopy, int initialNoDataRetries) {
        return result == PixelCopy.ERROR_SOURCE_NO_DATA && !hasSuccessfulCopy && initialNoDataRetries < 4
                ? INTERVAL_MS : FAILURE_INTERVAL_MS;
    }

    private void publish(int current, int width, int height) {
        synchronized (this) {
            if (current != generation || !enabled || disposed) return;
        }
        // A request from before a size change can still complete afterwards.
        if (copy == null || copy.getWidth() != width * REDUCTION
                || copy.getHeight() != height * REDUCTION) return;
        copy.getPixels(pixels, 0, copy.getWidth(), 0, 0, copy.getWidth(), copy.getHeight());
        reduce(pixels, copy.getWidth(), reduced, width, height, REDUCTION);
        blurWithBlackGutter(reduced, channels, scratch, width, height);
        final int paddedWidth = width + 2 * PADDING, paddedHeight = height + 2 * PADDING;
        final ByteBuffer rgba = encode(channels, width, height);
        int hash = 17;
        for (int i = 0, n = paddedWidth * paddedHeight; i < n; i++) {
            final int r = channels[i * 3], g = channels[i * 3 + 1], b = channels[i * 3 + 2];
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
            sink.onBackdrop(paddedWidth, paddedHeight, rgba);
        });
        schedule(current, INTERVAL_MS);
    }

    /** Black bars are part of the blur input, not added after filtering. */
    static void blurWithBlackGutter(int[] picture, int[] output, int[] temporary,
            int width, int height) {
        final int paddedWidth = width + 2 * PADDING, paddedHeight = height + 2 * PADDING;
        Arrays.fill(output, 0);
        for (int y = 0; y < height; y++) {
            System.arraycopy(picture, y * width * 3, output,
                    ((y + PADDING) * paddedWidth + PADDING) * 3, width * 3);
        }
        // Three box passes approximate a Gaussian (sigma about 2.4 pixels).
        for (int pass = 0; pass < BLUR_PASSES; pass++) {
            blurRows(output, temporary, paddedWidth, paddedHeight, BLUR_RADIUS);
            blurColumns(temporary, output, paddedWidth, paddedHeight, BLUR_RADIUS);
        }
    }

    /** The legacy prefix stays intact; the picture rect travels with pixels. */
    static ByteBuffer encode(int[] rgb, int pictureWidth, int pictureHeight) {
        final int width = pictureWidth + 2 * PADDING, height = pictureHeight + 2 * PADDING;
        final ByteBuffer rgba = ByteBuffer.allocateDirect(HEADER_BYTES + width * height * 4)
                .order(ByteOrder.nativeOrder());
        rgba.putInt(16, HEADER_MAGIC).putInt(20, HEADER_VERSION)
                .putInt(24, PADDING).putInt(28, PADDING)
                .putInt(32, pictureWidth).putInt(36, pictureHeight);
        rgba.position(HEADER_BYTES);
        for (int i = 0, n = width * height; i < n; i++) {
            rgba.put((byte) rgb[i * 3]).put((byte) rgb[i * 3 + 1])
                    .put((byte) rgb[i * 3 + 2]).put((byte) 0xFF);
        }
        return rgba;
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

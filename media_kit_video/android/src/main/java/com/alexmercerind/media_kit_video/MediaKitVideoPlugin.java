/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;
import android.content.Context;
import android.view.WindowManager;
import io.flutter.plugin.common.BasicMessageChannel;
import io.flutter.plugin.common.BinaryCodec;
import io.flutter.plugin.common.StandardMessageCodec;
import java.nio.ByteBuffer;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * MediaKitVideoPlugin
 */
public class MediaKitVideoPlugin implements FlutterPlugin, MethodCallHandler {
    /** The native video container of one platform view, for sibling overlays. */
    public static final class NativeVideoHost {
        /** Covers the whole playback viewport, letterbox bars included. */
        public final android.view.ViewGroup container;
        /** The video surface inside {@link #container}. */
        public final android.view.View surface;

        NativeVideoHost(android.view.ViewGroup container, android.view.View surface) {
            this.container = container;
            this.surface = surface;
        }
    }

    public interface NativeVideoHostListener {
        /** Called on the main thread before a host's views are torn down. */
        void onNativeVideoHostDisposed(int viewId);
    }

    // Main thread only. Platform view ids are unique per Flutter engine; this
    // app runs a single engine.
    private static final HashMap<Integer, HdrVideoPlatformView> nativeHosts = new HashMap<>();
    private static NativeVideoHostListener nativeHostListener;
    private static MediaKitVideoPlugin activePlugin;

    /** A video-only host sharing the existing mpv output; owns no decoder. */
    public static final class PictureInPictureHost {
        private final HdrVideoPlatformView view;
        private final VideoOutput output;

        private PictureInPictureHost(Context context, VideoOutput output) {
            this.output = output;
            view = new HdrVideoPlatformView(context, output, true, true,
                    java.util.Collections.emptyMap(), () -> {});
        }

        public android.view.View getView() { return view.getView(); }
        public boolean isReady() { return output.available() && view.eligible(); }
        public void dispose() { view.dispose(); }
    }

    public static PictureInPictureHost createPictureInPictureHost(Context context, long handle) {
        VideoOutput output = activePlugin == null ? null : activePlugin.videoOutputManager.findByHandle(handle);
        return output == null || !output.available() ? null : new PictureInPictureHost(context, output);
    }

    /** Resolves a live platform view id reported to Dart, or returns null. */
    public static NativeVideoHost nativeVideoHost(int viewId) {
        final HdrVideoPlatformView view = nativeHosts.get(viewId);
        return view == null ? null
            : new NativeVideoHost((android.view.ViewGroup) view.getView(), view.view);
    }

    public static void setNativeVideoHostListener(NativeVideoHostListener listener) {
        nativeHostListener = listener;
    }

    private MethodChannel channel;
    private BasicMessageChannel<ByteBuffer> backdropChannel;
    private VideoOutputManager videoOutputManager;
    private Context applicationContext;
    private java.util.concurrent.ExecutorService codecQueries;
    private final HashMap<Integer, HdrVideoPlatformView> hdrViews = new HashMap<>();

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "com.alexmercerind/media_kit_video");
        channel.setMethodCallHandler(this);
        // Pixel payloads bypass the method channel and its argument logging.
        backdropChannel = new BasicMessageChannel<>(flutterPluginBinding.getBinaryMessenger(),
            "com.alexmercerind/media_kit_video/backdrop", BinaryCodec.INSTANCE_DIRECT);

        applicationContext = flutterPluginBinding.getApplicationContext();
        codecQueries = java.util.concurrent.Executors.newSingleThreadExecutor();
        videoOutputManager = new VideoOutputManager(flutterPluginBinding.getTextureRegistry());
        activePlugin = this;
        flutterPluginBinding.getPlatformViewRegistry().registerViewFactory("media_kit_video/hdr",
            new PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                @Override public PlatformView create(Context context, int id, Object args) {
                    Map<?, ?> parameters = (Map<?, ?>) args;
                    long textureId = ((Number) parameters.get("textureId")).longValue();
                    VideoOutput output = videoOutputManager.findByTextureId(textureId);
                    if (output == null) throw new IllegalStateException("Video output disposed");
                    HdrVideoPlatformView view = new HdrVideoPlatformView(context, output,
                        Boolean.TRUE.equals(parameters.get("fullscreen")), parameters,
                        () -> {
                            hdrViews.remove(id);
                            if (nativeHosts.remove(id) != null && nativeHostListener != null) {
                                nativeHostListener.onNativeVideoHostDisposed(id);
                            }
                        });
                    hdrViews.put(id, view);
                    nativeHosts.put(id, view);
                    return view;
                }
            });

    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "HdrVideoView.UpdateLayout": {
                Number id = call.argument("viewId");
                HdrVideoPlatformView view = id == null ? null : hdrViews.get(id.intValue());
                if (view != null) view.updateLayout((Map<?, ?>) call.arguments);
                result.success(null);
                break;
            }
            case "VideoOutputManager.Create": {
                final long handle = Long.parseLong(call.argument("handle"));
                videoOutputManager.create(handle, (id, wid, subtitleWid, width, height, nativeSurface, hdrCapabilities, pictureInPicture) -> channel.invokeMethod("VideoOutput.Resize", new HashMap<String, Object>() {{
                    put("handle", handle);
                    put("id", id);
                    put("wid", wid);
                    put("subtitleWid", subtitleWid);
                    put("nativeSurface", nativeSurface);
                    put("hdrCapabilities", hdrCapabilities);
                    put("pictureInPicture", pictureInPicture);
                    put("rect", new HashMap<String, Object>() {{
                        put("left", 0);
                        put("top", 0);
                        put("width", width);
                        put("height", height);
                    }});
                }}), (width, height, message) -> {
                    final BasicMessageChannel<ByteBuffer> target = backdropChannel;
                    if (target == null) return;
                    message.putLong(0, handle).putInt(8, width).putInt(12, height);
                    target.send(message);
                });
                result.success(null);
                break;
            }
            case "VideoOutputManager.SetBackdropSampling": {
                final long handle = Long.parseLong(call.argument("handle"));
                videoOutputManager.setBackdropSampling(handle, Boolean.TRUE.equals(call.argument("enabled")),
                        call.argument("transfer"));
                result.success(null);
                break;
            }
            case "VideoOutputManager.PrepareForClose": {
                videoOutputManager.prepareForClose(Long.parseLong(call.argument("handle")));
                result.success(null);
                break;
            }
            case "Utils.SupportsNativeVideo": {
                WindowManager wm = (WindowManager) applicationContext.getSystemService(Context.WINDOW_SERVICE);
                final android.view.Display display = wm == null ? null : wm.getDefaultDisplay();
                final Map<?, ?> track = (Map<?, ?>) call.arguments;
                final android.os.Handler main = new android.os.Handler(android.os.Looper.getMainLooper());
                codecQueries.execute(() -> {
                    boolean supported = AndroidNativeDecoder.supports(display, track);
                    main.post(() -> result.success(supported));
                });
                break;
            }
            case "VideoOutputManager.SetSurfaceSize": {
                final long handle = Long.parseLong(call.argument("handle"));
                final int width = Integer.parseInt(call.argument("width"));
                final int height = Integer.parseInt(call.argument("height"));
                videoOutputManager.setSurfaceSize(handle, width, height);
                result.success(null);
                break;
            }
            case "VideoOutputManager.Dispose": {
                final long handle = Long.parseLong(call.argument("handle"));
                videoOutputManager.dispose(handle);
                result.success(null);
                break;
            }
            case "Utils.HdrCapabilities": {
                WindowManager wm = (WindowManager) applicationContext.getSystemService(Context.WINDOW_SERVICE);
                result.success(wm == null ? 0 : AndroidHdrCapabilities.mask(wm.getDefaultDisplay()));
                break;
            }
            case "Utils.IsEmulator": {
                result.success(Utils.isEmulator());
                break;
            }
            default: {
                result.notImplemented();
                break;
            }
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (activePlugin == this) activePlugin = null;
        if (codecQueries != null) codecQueries.shutdownNow();
        channel.setMethodCallHandler(null);
        backdropChannel = null;
        hdrViews.clear();
    }
}

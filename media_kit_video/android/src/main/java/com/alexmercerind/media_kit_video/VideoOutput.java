/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.os.Handler;
import android.view.Surface;
import java.util.ArrayList;
import android.os.Looper;
import android.util.Log;

import java.lang.reflect.Method;
import java.util.HashSet;
import java.util.Locale;
import java.util.Objects;

import io.flutter.view.TextureRegistry;

public class VideoOutput implements TextureRegistry.SurfaceProducer.Callback {
    private static final String TAG = "VideoOutput";
    private static final Method newGlobalObjectRef;
    private static final Method deleteGlobalObjectRef;
    private static final HashSet<Long> deletedGlobalObjectRefs = new HashSet<>();
    private static final Handler handler = new Handler(Looper.getMainLooper());

    static {
        try {
            // com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper is part of package:media_kit_libs_android_video & package:media_kit_libs_android_audio packages.
            // Use reflection to invoke methods of com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper.
            Class<?> mediaKitAndroidHelperClass = Class.forName("com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper");
            newGlobalObjectRef = mediaKitAndroidHelperClass.getDeclaredMethod("newGlobalObjectRef", Object.class);
            deleteGlobalObjectRef = mediaKitAndroidHelperClass.getDeclaredMethod("deleteGlobalObjectRef", long.class);
            newGlobalObjectRef.setAccessible(true);
            deleteGlobalObjectRef.setAccessible(true);
        } catch (Throwable e) {
            Log.i("media_kit", "package:media_kit_libs_android_video missing. Make sure you have added it to pubspec.yaml.");
            throw new RuntimeException("Failed to initialize com.alexmercerind.media_kit_video.VideoOutput.");
        }
    }

    private long id = 0;
    private long wid = 0;

    private final TextureUpdateCallback textureUpdateCallback;

    private final TextureRegistry.SurfaceProducer surfaceProducer;

    private final Object lock = new Object();
    private final ArrayList<HdrVideoPlatformView> nativeViews = new ArrayList<>();
    private HdrVideoPlatformView presentingView;
    private Surface selectedSurface;
    private int selectedCapabilities;
    private int selectedWidth;
    private int selectedHeight;
    private boolean disposed;

    long textureId() { return surfaceProducer.id(); }

    void attach(HdrVideoPlatformView view) {
        nativeViews.add(view);
        view.view.getHolder().setFixedSize(Math.max(1, surfaceProducer.getWidth()),
                Math.max(1, surfaceProducer.getHeight()));
    }

    void detach(HdrVideoPlatformView view) {
        nativeViews.remove(view);
        selectNativeSurface();
    }

    void selectNativeSurface() {
        if (disposed) return;
        HdrVideoPlatformView selected = null;
        for (HdrVideoPlatformView view : nativeViews) {
            if (view.eligible() && (selected == null || !selected.fullscreen || view.fullscreen)) {
                selected = view;
            }
        }
        presentingView = selected;
        Surface surface = null;
        try {
            surface = selected == null ? surfaceProducer.getSurface()
                    : selected.view.getHolder().getSurface();
        } catch (IllegalStateException ignored) {
            // The Flutter producer can be suspended while a native view detaches.
        }
        final int capabilities = selected == null ? 0
                : AndroidHdrCapabilities.mask(selected.view.getDisplay());
        int width = surfaceProducer.getWidth();
        int height = surfaceProducer.getHeight();
        if (surface == selectedSurface && capabilities == selectedCapabilities
                && width == selectedWidth && height == selectedHeight) return;
        selectedWidth = width;
        selectedHeight = height;
        selectedSurface = surface;
        selectedCapabilities = capabilities;
        final long oldWid = wid;
        wid = surface != null && surface.isValid() ? newGlobalObjectRef(surface) : 0;
        id = surfaceProducer.id();
        textureUpdateCallback.onTextureUpdate(id, wid, surfaceProducer.getWidth(),
                surfaceProducer.getHeight(), selected != null, capabilities);
        if (oldWid != 0) handler.postDelayed(() -> deleteGlobalObjectRef(oldWid), 5000);
    }


    VideoOutput(TextureRegistry textureRegistryReference, TextureUpdateCallback textureUpdateCallback) {
        this.textureUpdateCallback = textureUpdateCallback;

        surfaceProducer = textureRegistryReference.createSurfaceProducer();
        surfaceProducer.setCallback(this);
    }

    public void dispose() {
        synchronized (lock) {
            disposed = true;
            nativeViews.clear();
            presentingView = null;
            try {
                surfaceProducer.getSurface().release();
            } catch (Throwable e) {
                Log.e(TAG, "dispose", e);
            }
            try {
                surfaceProducer.release();
            } catch (Throwable e) {
                Log.e(TAG, "dispose", e);
            }
            onSurfaceCleanup();
        }
    }

    public void setSurfaceSize(int width, int height) {
        setSurfaceSize(width, height, false);
    }

    private void setSurfaceSize(int width, int height, boolean force) {
        synchronized (lock) {
            try {
                if (!force && surfaceProducer.getWidth() == width && surfaceProducer.getHeight() == height) {
                    return;
                }
                surfaceProducer.setSize(width, height);
                for (HdrVideoPlatformView view : nativeViews) {
                    view.view.getHolder().setFixedSize(width, height);
                }
                onSurfaceAvailable();
            } catch (Throwable e) {
                Log.e(TAG, "setSurfaceSize", e);
            }
        }
    }

    @Override
    public void onSurfaceAvailable() {
        synchronized (lock) {
            Log.i(TAG, "onSurfaceAvailable");
            if (disposed) return;
            selectNativeSurface();
        }
    }

    @Override
    public void onSurfaceCleanup() {
        synchronized (lock) {
            Log.i(TAG, "onSurfaceCleanup");
            if (!disposed && presentingView != null) return;
            textureUpdateCallback.onTextureUpdate(id, 0, surfaceProducer.getWidth(), surfaceProducer.getHeight(), false, 0);
            selectedSurface = null;
            if (wid != 0) {
                final long widReference = wid;
                handler.postDelayed(() -> deleteGlobalObjectRef(widReference), 5000);
            }
        }
    }

    private static long newGlobalObjectRef(Object object) {
        Log.i(TAG, String.format(Locale.ENGLISH, "newGlobalRef: object = %s", object));
        try {
            return (long) Objects.requireNonNull(newGlobalObjectRef.invoke(null, object));
        } catch (Throwable e) {
            Log.e(TAG, "newGlobalRef", e);
            return 0;
        }
    }

    private static void deleteGlobalObjectRef(long ref) {
        if (deletedGlobalObjectRefs.contains(ref)) {
            Log.i(TAG, String.format(Locale.ENGLISH, "deleteGlobalObjectRef: ref = %d ALREADY DELETED", ref));
            return;
        }
        if (deletedGlobalObjectRefs.size() > 100) {
            deletedGlobalObjectRefs.clear();
        }
        deletedGlobalObjectRefs.add(ref);
        Log.i(TAG, String.format(Locale.ENGLISH, "deleteGlobalObjectRef: ref = %d", ref));
        try {
            deleteGlobalObjectRef.invoke(null, ref);
        } catch (Throwable e) {
            Log.e(TAG, "deleteGlobalObjectRef", e);
        }
    }
}

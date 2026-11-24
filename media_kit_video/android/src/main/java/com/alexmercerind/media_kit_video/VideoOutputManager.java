/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.util.Log;

import java.util.HashMap;
import java.util.Locale;
import java.util.Objects;

import io.flutter.view.TextureRegistry;

public class VideoOutputManager {
    private static final String TAG = "VideoOutputManager";

    private final HashMap<Long, VideoOutput> videoOutputs = new HashMap<>();
    private final TextureRegistry textureRegistryReference;
    private final Object lock = new Object();

    VideoOutputManager(TextureRegistry textureRegistryReference) {
        this.textureRegistryReference = textureRegistryReference;
    }

    public void create(long handle, TextureUpdateCallback textureUpdateCallback,
                       VideoBackdropSampler.Sink backdropSink) {
        synchronized (lock) {
            Log.i(TAG, String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.create: %d", handle));
            if (!videoOutputs.containsKey(handle)) {
                final VideoOutput videoOutput = new VideoOutput(textureRegistryReference, textureUpdateCallback, backdropSink);
                videoOutputs.put(handle, videoOutput);
            }
        }
    }

    VideoOutput findByTextureId(long id) {
        for (VideoOutput output : videoOutputs.values()) {
            if (output.textureId() == id) return output;
        }
        return null;
    }

    public void dispose(long handle) {
        synchronized (lock) {
            Log.i(TAG, String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.dispose: %d", handle));
            if (videoOutputs.containsKey(handle)) {
                Objects.requireNonNull(videoOutputs.get(handle)).dispose();
                videoOutputs.remove(handle);
            }
        }
    }

    public void setBackdropSampling(long handle, boolean enabled) {
        synchronized (lock) {
            final VideoOutput output = videoOutputs.get(handle);
            if (output != null) output.setBackdropSampling(enabled);
        }
    }

    public void setSurfaceSize(long handle, int width, int height) {
        synchronized (lock) {
            Log.i(TAG, String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.setSurfaceSize: %d %d %d", handle, width, height));
            if (videoOutputs.containsKey(handle)) {
                Objects.requireNonNull(videoOutputs.get(handle)).setSurfaceSize(width, height);
            }
        }
    }
}

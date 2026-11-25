package com.alexmercerind.media_kit_video;

public interface TextureUpdateCallback {
    void onTextureUpdate(long id, long wid, long subtitleWid, int width, int height, boolean nativeSurface, int hdrCapabilities);
}

package com.alexmercerind.media_kit_video;

import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.view.Display;
import java.util.Map;

/** Verify codec and display together before selecting direct surface output. */
final class AndroidNativeDecoder {
    static boolean supports(Display display, Map<?, ?> track) {
        if (display == null) return false;
        final String codec = String.valueOf(track.get("codec"));
        final int width = number(track, "demux-w"), height = number(track, "demux-h");
        final int profile = number(track, "dolby-vision-profile");
        if (width < 1 || height < 1) return false;
        String mime;
        switch (codec) {
            case "hevc": mime = "video/hevc"; break;
            case "h264": mime = "video/avc"; break;
            case "vp9": mime = "video/x-vnd.on2.vp9"; break;
            case "av1": mime = "video/av01"; break;
            default: return false;
        }
        final boolean dolby = ("hevc".equals(codec) && (profile == 5 || profile == 8))
                || ("av1".equals(codec) && profile == 10);
        final String gamma = String.valueOf(track.get("demux-gamma"));
        final int desired = dolby ? Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION :
                "hlg".equals(gamma) ? Display.HdrCapabilities.HDR_TYPE_HLG :
                Display.HdrCapabilities.HDR_TYPE_HDR10;
        boolean displaySupports = false;
        for (int type : display.getHdrCapabilities().getSupportedHdrTypes())
            displaySupports |= type == desired;
        if (!displaySupports || (profile != 0 && !dolby)) return false;
        try {
            if (dolby) mime = "video/dolby-vision";
            MediaFormat format = MediaFormat.createVideoFormat(mime, width, height);
            if (dolby) format.setInteger(MediaFormat.KEY_PROFILE,
                    profile == 5 ? 32 : profile == 10 ? 1024 : 256);
            Object fps = track.get("demux-fps");
            if (fps instanceof Number && Double.isFinite(((Number)fps).doubleValue())
                    && ((Number)fps).doubleValue() > 0)
                format.setFloat(MediaFormat.KEY_FRAME_RATE, ((Number)fps).floatValue());
            for (MediaCodecInfo info : new MediaCodecList(MediaCodecList.REGULAR_CODECS).getCodecInfos()) {
                if (info.isEncoder() || (android.os.Build.VERSION.SDK_INT >= 29 && info.isSoftwareOnly())) continue;
                try {
                    if (info.getCapabilitiesForType(mime).isFormatSupported(format)) return true;
                } catch (IllegalArgumentException ignored) {}
            }
        } catch (RuntimeException unavailable) {
            return false;
        }
        return false;
    }

    private static int number(Map<?, ?> values, String key) {
        Object value = values.get(key);
        return value instanceof Number ? ((Number)value).intValue() : 0;
    }
}

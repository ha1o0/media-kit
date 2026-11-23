package com.alexmercerind.media_kit_video;

import android.os.Build;
import android.view.Display;

/** HDR types accepted by the active display; never infer support from a codec. */
final class AndroidHdrCapabilities {
    static int mask(Display display) {
        if (Build.VERSION.SDK_INT < 26 || display == null) return 0;
        int mask = 0;
        for (int type : display.getHdrCapabilities().getSupportedHdrTypes()) {
            if (type == Display.HdrCapabilities.HDR_TYPE_HDR10) mask |= 1;
            if (type == Display.HdrCapabilities.HDR_TYPE_HLG) mask |= 2;
        }
        return mask;
    }
}

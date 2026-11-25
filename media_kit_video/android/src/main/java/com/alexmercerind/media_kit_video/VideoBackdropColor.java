package com.alexmercerind.media_kit_video;

/** HDR display-referred pixels to the SDR copy used by playback glass. */
final class VideoBackdropColor {
    private VideoBackdropColor() {}

    static double pqToLinear(double value) {
        final double p = Math.pow(Math.max(0, value), 1.0 / 78.84375);
        return Math.pow(Math.max(p - 0.8359375, 0) /
                Math.max(18.8515625 - 18.6875 * p, 1e-8), 1.0 / 0.1593017578125);
    }

    static double hlgToLinear(double value) {
        return value <= 0.5 ? value * value / 3 :
                (Math.exp((value - 0.55991073) / 0.17883277) + 0.28466892) / 12;
    }

    static float halfToFloat(short bits) {
        final int v = bits & 0xffff;
        final int sign = (v & 0x8000) << 16;
        final int exponent = (v >>> 10) & 31;
        final int fraction = v & 1023;
        if (exponent == 0) return (v < 0x8000 ? 1 : -1) * Math.scalb((float) fraction, -24);
        if (exponent == 31) return 0; // Invalid decoder pixels must not poison the blur.
        return Float.intBitsToFloat(sign | ((exponent + 112) << 23) | (fraction << 13));
    }

    static int toSdr(float red, float green, float blue, boolean hlg) {
        double r = hlg ? hlgToLinear(red) : pqToLinear(red);
        double g = hlg ? hlgToLinear(green) : pqToLinear(green);
        double b = hlg ? hlgToLinear(blue) : pqToLinear(blue);
        // PQ is absolute (10,000 nits); HLG uses a 1,000 nit reference display.
        // Apply the HLG OOTF to luminance, preserving chromaticity.
        final double scale = hlg
                ? (1000.0 / 203) * Math.pow(Math.max(0, .2627 * r + .6780 * g + .0593 * b), .2)
                : 10000.0 / 203;
        r *= scale; g *= scale; b *= scale;
        // BT.2020 linear RGB to BT.709 linear RGB. The bitmap copy deliberately
        // retains the source encoding, so Android cannot normalize 10,000 nits
        // to SDR white and turn an ordinary HDR scene nearly black.
        final double sr = 1.660491 * r - .587641 * g - .072850 * b;
        final double sg = -.124550 * r + 1.132900 * g - .008349 * b;
        final double sb = -.018151 * r - .100579 * g + 1.118730 * b;
        final double peak = Math.max(0, Math.max(sr, Math.max(sg, sb)));
        final double shoulder = peak <= .75 ? 1 :
                (.75 + .25 * (1 - Math.exp(-4 * (peak - .75)))) / peak;
        return 0xff000000 | (srgb(sr * shoulder) << 16) |
                (srgb(sg * shoulder) << 8) | srgb(sb * shoulder);
    }

    private static int srgb(double value) {
        value = Math.max(0, Math.min(1, value));
        final double encoded = value <= .0031308 ? 12.92 * value :
                1.055 * Math.pow(value, 1.0 / 2.4) - .055;
        return (int) Math.round(encoded * 255);
    }
}

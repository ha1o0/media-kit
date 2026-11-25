import 'dart:ui' show Size;

/// Dolby Vision P5 and P8 require gpu-next to apply their per-frame RPU mapping.
/// Keep the configured output for other files and explicit embed outputs.
String androidVideoOutputForTracks(String configured, Object? tracks,
    {bool nativeHdr = false}) {
  return configured == 'gpu' &&
          (_hasSelectedMappedDolbyVision(tracks) ||
              (nativeHdr && androidTracksHaveHdr(tracks)))
      ? 'gpu-next'
      : configured;
}

/// P5/P8 require raw components and per-frame RPU metadata. Prefer GPU transport
/// at every resolution; the native decoder accepts it only with gpu-next and
/// GL_EXT_YUV_target, otherwise it tries P010 copy-back before software decoding.
/// Explicit compatibility/copy modes keep their readable frames. Profile 20
/// retains its established P010/base-view path.
String androidHardwareDecoderForTracks(
  String configured,
  String videoOutput,
  Object? tracks, {
  bool nativeHdr = false,
}) {
  if ((videoOutput == 'gpu' || videoOutput == 'gpu-next') &&
      const {
        '',
        'yes',
        'auto',
        'auto-safe',
        'auto-unsafe',
        'auto-copy',
        'auto-copy-safe',
        'auto-copy-unsafe',
        'mediacodec',
        'mediacodec-copy',
        'mediacodec,mediacodec-copy',
      }.contains(configured) &&
      (_hasSelectedMappedDolbyVision(tracks) ||
          (nativeHdr && androidTracksHaveHdr(tracks)))) {
    if (_hasSelectedDolbyVisionProfile(tracks, const {5, 8})) {
      return const {
        'auto-copy',
        'auto-copy-safe',
        'auto-copy-unsafe',
        'mediacodec-copy',
      }.contains(configured)
          ? 'mediacodec-copy'
          : 'mediacodec,mediacodec-copy';
    }
    if (nativeHdr &&
        androidTracksHaveHdr(tracks) &&
        !_hasSelectedDolbyVisionProfile(tracks, const {20})) {
      if (configured == 'mediacodec') return configured;
      if (configured == 'mediacodec,mediacodec-copy' &&
          androidTracksExceedCopyBudget(tracks)) {
        return configured;
      }
    }
    return 'mediacodec-copy';
  }
  return configured;
}

bool _hasSelectedMappedDolbyVision(Object? tracks) =>
    _hasSelectedDolbyVisionProfile(tracks, const {5, 8, 20});

bool androidTracksUseRawDolbyGpu(Object? tracks) =>
    _hasSelectedDolbyVisionProfile(tracks, const {5, 8});

bool _hasSelectedDolbyVisionProfile(Object? tracks, Set<int> profiles) {
  if (tracks is! List) return false;
  for (final track in tracks) {
    if (track is Map &&
        track['type'] == 'video' &&
        track['selected'] == true &&
        profiles.contains(track['dolby-vision-profile'])) {
      return true;
    }
  }
  return false;
}

bool androidTracksExceedCopyBudget(Object? tracks) {
  if (tracks is! List) return false;
  for (final track in tracks) {
    if (track is! Map ||
        track['type'] != 'video' ||
        track['selected'] != true) {
      continue;
    }
    final width = track['demux-w'], height = track['demux-h'];
    if (width is! num ||
        height is! num ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      continue;
    }
    final pixels = width * height;
    final fps = track['demux-fps'];
    // Retain the established 4K60 path, but avoid a full CPU round trip
    // for every 4K120 frame. Unknown frame rates keep their previous policy.
    if (pixels > 4096 * 2304 ||
        (fps is num &&
            fps.isFinite &&
            fps > 0 &&
            pixels * fps > 4096 * 2304 * 60)) {
      return true;
    }
  }
  return false;
}

/// Demux metadata is available before decoder setup, including HDR10 and HLG.
bool androidTracksHaveHdr(Object? tracks) =>
    tracks is List &&
    tracks.any((track) =>
        track is Map &&
        track['type'] == 'video' &&
        track['selected'] == true &&
        (const {'pq', 'hlg'}.contains(track['demux-gamma']) ||
            const {5, 7, 8, 10, 20}.contains(track['dolby-vision-profile'])));

/// Beyond 4K the surface costs more than the decoder: an 8K surface is 33
/// million pixels to fill and compose for every frame, of which a phone shows
/// about a seventh. Render such a source at the size that covers the display
/// in either orientation, so no fit mode loses visible detail. Sources up to
/// 4K keep their own size.
Size androidSurfaceSize(int width, int height, Size display,
    {bool highFrameRate = false}) {
  final source = Size(width.toDouble(), height.toDouble());
  if (!highFrameRate && width * height <= 4096 * 2304) return source;
  if (!display.longestSide.isFinite || display.shortestSide < 1) return source;
  final byLong = display.longestSide / source.longestSide;
  final byShort = display.shortestSide / source.shortestSide;
  final scale = byLong > byShort ? byLong : byShort;
  if (scale >= 1) return source;
  // Even dimensions keep 4:2:0 hardware frames aligned.
  double even(double value) {
    final rounded = value.round();
    final aligned = rounded.isEven ? rounded : rounded + 1;
    return (aligned < 2 ? 2 : aligned).toDouble();
  }

  return Size(even(width * scale), even(height * scale));
}

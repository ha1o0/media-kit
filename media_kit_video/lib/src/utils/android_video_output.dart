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

/// Keep P5/P8 as raw P010 rather than letting Android's external texture sampler
/// convert its components to RGB before libplacebo can apply Dolby reshaping.
/// This still uses the hardware decoder; only decoded-frame transport is copied.
///
/// That copy moves every decoded picture through system memory and back to the
/// GPU: about 25 MB per 4K frame and 100 MB per 8K frame. A native HDR surface
/// shows the HDR10/HLG base layer without any per-frame mapping, so the frames
/// may stay on the GPU there. They do so when the user chose the performance
/// decoder, for pictures larger than 4K, and for frame rates the copy cannot
/// keep up with (4K at 120 fps moves about 3 GB per second each way). Profile
/// 5 has no such base layer and always needs its planes.
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
    if (nativeHdr &&
        androidTracksHaveHdr(tracks) &&
        !_hasSelectedDolbyVisionProfile(tracks, const {5})) {
      if (configured == 'mediacodec') return configured;
      if (configured == 'mediacodec,mediacodec-copy' &&
          (_selectedVideoExceeds4k(tracks) ||
              _selectedVideoExceedsCopyRate(tracks))) {
        return configured;
      }
    }
    return 'mediacodec-copy';
  }
  return configured;
}

bool _hasSelectedMappedDolbyVision(Object? tracks) =>
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

bool _selectedVideoExceeds4k(Object? tracks) {
  if (tracks is! List) return false;
  for (final track in tracks) {
    if (track is! Map ||
        track['type'] != 'video' ||
        track['selected'] != true) {
      continue;
    }
    final width = track['demux-w'], height = track['demux-h'];
    if (width is num && height is num && width * height > 4096 * 2304) {
      return true;
    }
  }
  return false;
}

/// Pixel rates up to 4K at 60 fps keep the copy as before. Beyond that (4K at
/// 120 fps, for example) frames stay on the GPU, with the copy as fallback.
/// Files without a container frame rate keep the copy.
bool _selectedVideoExceedsCopyRate(Object? tracks) {
  if (tracks is! List) return false;
  for (final track in tracks) {
    if (track is! Map ||
        track['type'] != 'video' ||
        track['selected'] != true) {
      continue;
    }
    final width = track['demux-w'], height = track['demux-h'];
    final fps = track['demux-fps'];
    if (width is num &&
        height is num &&
        fps is num &&
        fps.isFinite &&
        width * height * fps > 4096 * 2304 * 60) {
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
            const {5, 7, 8}.contains(track['dolby-vision-profile'])));

/// Beyond 4K the surface costs more than the decoder: an 8K surface is 33
/// million pixels to fill and compose for every frame, of which a phone shows
/// about a seventh. Render such a source at the size that covers the display
/// in either orientation, so no fit mode loses visible detail. Sources up to
/// 4K keep their own size.
Size androidSurfaceSize(int width, int height, Size display) {
  final source = Size(width.toDouble(), height.toDouble());
  if (width * height <= 4096 * 2304) return source;
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

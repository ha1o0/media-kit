/// Dolby Vision P5 and P8 require gpu-next to apply their per-frame RPU mapping.
/// Keep the configured output for other files and explicit embed outputs.
String androidVideoOutputForTracks(String configured, Object? tracks) {
  return configured == 'gpu' && _hasSelectedMappedDolbyVision(tracks)
      ? 'gpu-next'
      : configured;
}

/// Keep P5/P8 as raw P010 rather than letting Android's external texture sampler
/// convert its components to RGB before libplacebo can apply Dolby reshaping.
/// This still uses the hardware decoder; only decoded-frame transport is copied.
String androidHardwareDecoderForTracks(
  String configured,
  String videoOutput,
  Object? tracks,
) {
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
      _hasSelectedMappedDolbyVision(tracks)) {
    return 'mediacodec-copy';
  }
  return configured;
}

bool _hasSelectedMappedDolbyVision(Object? tracks) {
  if (tracks is! List) return false;
  for (final track in tracks) {
    if (track is Map &&
        track['type'] == 'video' &&
        track['selected'] == true &&
        const {5, 8}.contains(track['dolby-vision-profile'])) {
      return true;
    }
  }
  return false;
}

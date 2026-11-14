/// Profile 5 has no HDR10-compatible base layer. The legacy GPU renderer drops
/// its Dolby Vision mapping, so this file needs gpu-next even in compatibility
/// mode. Keep the configured output for other files and explicit embed outputs.
String androidVideoOutputForTracks(String configured, Object? tracks) {
  return configured == 'gpu' && _hasSelectedProfile5(tracks)
      ? 'gpu-next'
      : configured;
}

/// Keep P5 as raw P010 rather than letting Android's external texture sampler
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
      }.contains(configured) &&
      _hasSelectedProfile5(tracks)) {
    return 'mediacodec-copy';
  }
  return configured;
}

bool _hasSelectedProfile5(Object? tracks) {
  if (tracks is! List) return false;
  for (final track in tracks) {
    if (track is Map &&
        track['type'] == 'video' &&
        track['selected'] == true &&
        track['dolby-vision-profile'] == 5) {
      return true;
    }
  }
  return false;
}

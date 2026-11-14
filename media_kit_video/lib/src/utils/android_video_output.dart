/// Profile 5 has no HDR10-compatible base layer. The legacy GPU renderer drops
/// its Dolby Vision mapping, so this file needs gpu-next even in compatibility
/// mode. Keep the configured output for other files and explicit embed outputs.
String androidVideoOutputForTracks(String configured, Object? tracks) {
  if (configured != 'gpu' || tracks is! List) return configured;
  for (final track in tracks) {
    if (track is Map &&
        track['type'] == 'video' &&
        track['selected'] == true &&
        track['dolby-vision-profile'] == 5) {
      return 'gpu-next';
    }
  }
  return configured;
}

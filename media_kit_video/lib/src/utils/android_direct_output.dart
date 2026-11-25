/// A direct decoder Surface cannot apply mpv video filters or shaders.
/// The native VO still renders subtitle tracks through mpv/libass.
bool androidDirectOutputEligible({
  required String decoder,
  required Object? tracks,
  required String hdrHint,
  required String filters,
  required String shaders,
  required String deinterlace,
}) {
  if (!const {'mediacodec', 'mediacodec,mediacodec-copy'}.contains(decoder) ||
      hdrHint == 'no' ||
      !const {'', '[]'}.contains(filters) ||
      !const {'', '[]'}.contains(shaders) ||
      !const {'no', 'false', '0', ''}.contains(deinterlace)) {
    return false;
  }
  if (tracks is! List) return false;
  return tracks.any((track) =>
      track is Map &&
      track['type'] == 'video' &&
      track['selected'] == true &&
      const {'h264', 'hevc', 'vp9', 'av1'}.contains(track['codec']) &&
      (track['demux-rotate'] == null || track['demux-rotate'] == 0) &&
      (const {'pq', 'hlg'}.contains(track['demux-gamma']) ||
          const {5, 8, 10}.contains(track['dolby-vision-profile'])));
}

bool androidDirectOutputNeedsRenderer(String property, String value) {
  switch (property) {
    case 'hwdec':
      return !const {'mediacodec', 'mediacodec,mediacodec-copy'}
          .contains(value);
    case 'vf':
    case 'glsl-shaders':
      return !const {'', '[]'}.contains(value);
    case 'deinterlace':
      return !const {'no', 'false', '0', ''}.contains(value);
    case 'target-colorspace-hint':
      return value == 'no';
    case 'sub-hdr-peak':
    case 'image-subs-hdr-peak':
      return value != 'sdr' && double.tryParse(value) != 203;
    case 'secondary-sub-hdr-peak':
    case 'secondary-image-subs-hdr-peak':
      return value != 'shared' &&
          value != 'sdr' &&
          double.tryParse(value) != 203;
    case 'brightness':
    case 'contrast':
    case 'saturation':
    case 'gamma':
    case 'hue':
      return double.tryParse(value) != 0;
    default:
      return false;
  }
}

bool androidDirectCommandNeedsRenderer(List<String> command) {
  final args = command.where((part) => part != 'no-osd').toList();
  if (args.length < 2) return false;
  if (args.first == 'vf') return args[1] != 'remove' && args[1] != 'clr';
  return args.length > 2 &&
      args[0] == 'change-list' &&
      args[1] == 'glsl-shaders' &&
      args[2] != 'remove' &&
      args[2] != 'clr';
}

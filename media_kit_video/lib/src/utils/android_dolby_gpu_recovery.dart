/// Recover a failed Dolby hardware-frame import without abandoning mpv's GPU
/// renderer or HDR surface. A new instance belongs to one loaded file.
class AndroidDolbyGpuRecovery {
  bool _attempted = false;
  Future<bool>? _pending;

  static bool isInteropError(String prefix, String level, String text) =>
      (level == 'error' || level == 'fatal') &&
      prefix.startsWith('vo/gpu-next') &&
      const [
        'Initializing texture for hardware decoding failed',
        'Mapping hardware decoded surface failed',
        'Failed mapping hwdec frame',
        'Failed updating frames',
        'Failed rendering frame',
      ].any(text.contains);

  Future<bool> recover({
    required Future<String> Function() readDecoder,
    required Future<void> Function(String) writeDecoder,
    required bool Function() isCurrent,
  }) {
    if (_pending != null) return _pending!;
    if (_attempted) return Future.value(false);
    _attempted = true;
    return _pending = _recover(readDecoder, writeDecoder, isCurrent)
        .whenComplete(() => _pending = null);
  }

  Future<bool> _recover(
    Future<String> Function() readDecoder,
    Future<void> Function(String) writeDecoder,
    bool Function() isCurrent,
  ) async {
    try {
      if (!isCurrent()) return false;
      final decoder = await readDecoder();
      if (!isCurrent() || decoder != 'mediacodec') return false;
      await writeDecoder('mediacodec-copy');
      return true;
    } catch (_) {
      return false;
    }
  }
}

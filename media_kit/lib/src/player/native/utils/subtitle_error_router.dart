import 'dart:async';

/// Keeps failed external-subtitle commands out of primary playback recovery.
/// Unscoped transport diagnostics wait for the command and its queued logs;
/// explicit media/decoder failures always remain playback errors.
class NativeSubtitleErrorRouter {
  final void Function(String error) emitError;
  final _loads = <Object, _SubtitleLoad>{};
  final _deferred = <_TransportError>[];
  String? _mediaUri;

  NativeSubtitleErrorRouter({required this.emitError});

  void reset({String? mediaUri}) {
    _mediaUri = mediaUri;
    _loads.clear();
    _deferred.clear();
  }

  Object begin(String uri) {
    final token = Object();
    _loads[token] = _SubtitleLoad(uri);
    return token;
  }

  void finish(Object token, {required bool failed}) {
    final load = _loads.remove(token);
    if (load == null) return;
    load.finished = true;
    load.failed = failed;
    _deferred.removeWhere((error) {
      if (error.loads.any((load) => !load.finished)) return false;
      final subtitleOnly = error.loads.every((load) =>
          load.failed &&
          (load.sawSubtitleError ||
              _sameEndpoint(
                  _tcpEndpoint(error.text), Uri.tryParse(load.uri))) &&
          !load.sawPlaybackError);
      final text = error.text;
      emitError(subtitleOnly ? '[sub] $text' : text);
      return true;
    });
  }

  void playbackFailed(String error) {
    for (final load in _loads.values) {
      load.sawPlaybackError = true;
    }
    for (final pending in _deferred) {
      emitError(pending.text);
    }
    _deferred.clear();
    emitError(error);
  }

  void logError(String prefix, String text) {
    if (prefix == 'ffmpeg') {
      if (!text.startsWith('tcp:')) return;
      if (_loads.isNotEmpty && !_targetsOnlyPrimaryEndpoint(text)) {
        _deferred.add(_TransportError(text, _loads.values.toList()));
        return;
      }
    } else if (!const {'file', 'stream', 'cplayer', 'vd', 'ad'}
        .contains(prefix)) {
      return;
    }

    final primaryResource =
        _mediaUri != null && _mentionsResource(text, _mediaUri!);
    final subtitleLoads = _loads.values.where((load) =>
        load.resources.any((resource) => _mentionsResource(text, resource)));
    if (!primaryResource &&
        prefix != 'vd' &&
        prefix != 'ad' &&
        subtitleLoads.isNotEmpty) {
      for (final load in subtitleLoads) {
        load.sawSubtitleError = true;
      }
      emitError('[sub] $text');
      return;
    }

    if (prefix != 'ad') {
      for (final load in _loads.values) {
        load.sawPlaybackError = true;
      }
    }
    emitError(text);
  }

  bool _targetsOnlyPrimaryEndpoint(String text) {
    final endpoint = _tcpEndpoint(text);
    final media = Uri.tryParse(_mediaUri ?? '');
    if (!_sameEndpoint(endpoint, media)) return false;
    return !_loads.values
        .any((load) => _sameEndpoint(endpoint, Uri.tryParse(load.uri)));
  }

  static Uri? _tcpEndpoint(String text) {
    final match = RegExp(r'tcp://[^\s]+').firstMatch(text);
    return Uri.tryParse(match?.group(0) ?? '');
  }

  static bool _sameEndpoint(Uri? first, Uri? second) =>
      first != null &&
      second != null &&
      first.host.isNotEmpty &&
      first.host == second.host &&
      first.port == second.port;

  static bool _mentionsResource(String text, String resource) {
    final variants = <String>{resource};
    try {
      variants.add(Uri.decodeComponent(resource));
      final uri = Uri.parse(resource);
      if (uri.scheme == 'file') {
        variants.add(uri.toFilePath(
            windows: uri.host.isNotEmpty ||
                RegExp(r'^/[a-zA-Z]:/').hasMatch(uri.path)));
      }
    } catch (_) {}
    return variants.any((value) =>
        value.isNotEmpty &&
        (text.endsWith(value) ||
            text.endsWith('$value.') ||
            text.contains('"$value"') ||
            text.contains("'$value'")));
  }
}

/// Waits briefly for log messages queued behind a subtitle command.
///
/// A drained libmpv event queue completes the wait immediately. The timeout is
/// a safety net for renderers which continuously emit logs and therefore never
/// produce an idle queue boundary.
class NativeSubtitleLogDrainBarrier {
  static const Duration defaultTimeout = Duration(milliseconds: 500);

  final Duration timeout;
  final void Function(Object token, {required bool failed}) finish;
  final List<_PendingSubtitleLogDrain> _pending = [];

  NativeSubtitleLogDrainBarrier({
    required this.finish,
    this.timeout = defaultTimeout,
  });

  Future<void> wait({required Object token, required bool failed}) {
    final pending = _PendingSubtitleLogDrain(token, failed);
    _pending.add(pending);
    pending.timer = Timer(timeout, () => _complete(pending));
    return pending.completer.future;
  }

  void completeAll() {
    for (final pending in _pending.toList(growable: false)) {
      _complete(pending);
    }
  }

  void _complete(_PendingSubtitleLogDrain pending) {
    if (!_pending.remove(pending)) return;
    pending.timer?.cancel();
    try {
      finish(pending.token, failed: pending.failed);
    } finally {
      if (!pending.completer.isCompleted) {
        pending.completer.complete();
      }
    }
  }
}

class _PendingSubtitleLogDrain {
  final Object token;
  final bool failed;
  final Completer<void> completer = Completer<void>();
  Timer? timer;

  _PendingSubtitleLogDrain(this.token, this.failed);
}

class _SubtitleLoad {
  final String uri;
  late final Set<String> resources = {uri};
  bool finished = false;
  bool failed = false;
  bool sawSubtitleError = false;
  bool sawPlaybackError = false;

  _SubtitleLoad(this.uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed != null && parsed.path.toLowerCase().endsWith('.idx')) {
      final extension = parsed.path.endsWith('.IDX') ? '.SUB' : '.sub';
      final stem = parsed.path.substring(0, parsed.path.length - 4);
      resources.add(parsed.replace(path: '$stem$extension').toString());
    }
  }
}

class _TransportError {
  final String text;
  final List<_SubtitleLoad> loads;

  _TransportError(this.text, this.loads);
}

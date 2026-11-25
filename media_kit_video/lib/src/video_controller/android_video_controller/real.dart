/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:media_kit_video/src/utils/android_video_output.dart';
import 'package:media_kit_video/src/utils/android_direct_output.dart';
import 'package:media_kit_video/src/utils/android_dolby_gpu_recovery.dart';
import 'package:media_kit_video/src/utils/video_backdrop_message.dart';
import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/utils/query_decoders.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

/// {@template android_video_controller}
///
/// AndroidVideoController
/// ----------------------
///
/// The [PlatformVideoController] implementation based on native JNI & C/C++ used on Android.
///
/// {@endtemplate}
class AndroidVideoController extends PlatformVideoController {
  /// Whether [AndroidVideoController] is supported on the current platform or not.
  static bool get supported => Platform.isAndroid;

  /// Pointer address to the global object reference of `android.view.Surface` i.e. `(intptr_t)(*android.view.Surface)`.
  final ValueNotifier<int?> wid = ValueNotifier<int?>(null);

  /// [Lock] used to synchronize [onLoadHooks], [onUnloadHooks] & [subscription].
  final lock = Lock();

  NativePlayer get platform => player.platform as NativePlayer;

  Future<void> setProperty(String key, String value) async {
    await platform.setProperty(key, value, waitForInitialization: false);
  }

  Future<void> setProperties(Map<String, String> properties,
      {bool asynchronous = false, bool Function()? isCurrent}) async {
    for (final entry in properties.entries) {
      if (_closing || _disposed || isCurrent?.call() == false) return;
      if (asynchronous) {
        await platform.setPropertyAsync(entry.key, entry.value,
            waitForInitialization: false);
      } else {
        await setProperty(entry.key, entry.value);
      }
    }
  }

  String? _fileVideoOutput;
  bool _nativeHdrSupported = false;
  int _surfaceHdrCapabilities = 0;
  bool _nativeSurfaceSelected = false;
  bool _disposed = false;
  bool _observesTarget = false;
  bool _nativeSurfaceFailed = false;
  StreamSubscription<PlayerLog>? _renderLogSubscription;
  String _lastOutputSummary = '';

  int _backdropConsumers = 0;
  int _backdropDecodeGeneration = 0;
  ui.Image? _retiredBackdrop;
  VideoBackdropFrame? _backdropFrame;
  String _backdropTransfer = '';
  bool _limitSurfaceToDisplay = false;
  bool _closing = false;
  bool _supportsDirectOutput = false;
  bool _directAllowed = false;
  bool _directActive = false;
  int _subtitleWid = 0;
  String _directTransfer = '';
  String _configuredDecoder = '';
  bool _preparingOutput = false;
  int _outputGeneration = 0;
  Completer<void>? _surfaceReady;
  String? _appliedSurfaceKey;
  AndroidDolbyGpuRecovery? _dolbyGpuRecovery;

  String _surfaceKey(String output) => '${wid.value}|'
      '${output == 'mediacodec_embed' ? _subtitleWid : 0}|'
      '${rect.value}|$_surfaceHdrCapabilities|$_nativeSurfaceSelected|$output';

  bool get _requestedSurfaceReady =>
      (wid.value ?? 0) != 0 &&
      _nativeSurfaceSelected == androidNativeSurface.value &&
      (!androidNativeSurface.value || !_directAllowed || _subtitleWid != 0);

  @override
  Future<void> prepareForClose() async {
    if (_disposed || _closing) return;
    _closing = true;
    _directAllowed = false;
    _backdropDecodeGeneration++;
    final handle = await player.handle;
    if (_disposed) return;
    await _channel.invokeMethod('VideoOutputManager.PrepareForClose', {
      'handle': handle.toString(),
    });
    // Disable the video track on mpv's thread. Changing vo to null here would
    // reopen the decoder against that new VO and queue another seek. Retain
    // the playback clock until the screen saves its position and disposes it.
    unawaited(platform
        .setPropertyAsync('vid', 'no', waitForInitialization: false)
        .catchError((Object _) {}));
  }

  Future<void> _leaveDirectOutput() async {
    if (!_directActive || _closing || _disposed) return;
    _directAllowed = false;
    await widListener();
  }

  Future<void> _onRenderLog(PlayerLog entry, int generation) async {
    if (_disposed || _closing || generation != _outputGeneration) return;
    if (_directActive &&
        (entry.level == 'error' || entry.level == 'fatal') &&
        (entry.text.contains('Could not open codec') ||
            entry.text.contains('Error while decoding') ||
            entry.text.contains('Cannot load libass') ||
            entry.text.contains('Failed to create hwdevice'))) {
      unawaited(_leaveDirectOutput());
    }
    final recovery = _dolbyGpuRecovery;
    if (!_directActive &&
        !_preparingOutput &&
        recovery != null &&
        AndroidDolbyGpuRecovery.isInteropError(
            entry.prefix, entry.level, entry.text)) {
      bool current() =>
          !_disposed &&
          !_closing &&
          !_preparingOutput &&
          !_directActive &&
          generation == _outputGeneration &&
          identical(recovery, _dolbyGpuRecovery);
      // A failed frame import is not proof that the HDR display Surface failed.
      // First retry readable hardware frames on the same mpv/HDR output.
      final recovered = await recovery.recover(
        readDecoder: () =>
            platform.getProperty('hwdec-current', waitForInitialization: false),
        writeDecoder: (decoder) => platform.setPropertyAsync(
            'file-local-options/hwdec', decoder,
            waitForInitialization: false),
        isCurrent: current,
      );
      if (recovered || !current()) return;
    }
    if (_disposed ||
        _closing ||
        _nativeSurfaceFailed ||
        !_nativeSurfaceSelected) {
      return;
    }
    if (entry.level == 'error' || entry.level == 'fatal') {
      final failed = entry.text.contains('Could not create EGL surface') ||
          entry.text.contains('Failed to set context') ||
          entry.text.contains('Failed restoring SDR EGL surface') ||
          entry.text.contains('Failed rendering frame');
      if (failed) {
        _nativeSurfaceFailed = true;
        scheduleMicrotask(() {
          if (!_disposed && !_closing && generation == _outputGeneration) {
            nativeHdrActive.value = false;
            androidNativeSurface.value = false;
          }
        });
      }
    }
  }

  Future<void> _beforePropertySet(String property, String value) async {
    if (_directActive && androidDirectOutputNeedsRenderer(property, value)) {
      await _leaveDirectOutput();
    }
  }

  Future<void> _beforeCommand(List<String> command) async {
    if (_directActive && androidDirectCommandNeedsRenderer(command)) {
      await _leaveDirectOutput();
    }
  }

  @override
  VideoBackdropFrame? get backdropFrame => _backdropFrame;

  @override
  void retainBackdrop() {
    if (_disposed || _closing) return;
    _ensureBackdropChannel();
    if (_backdropConsumers++ == 0) unawaited(_setBackdropSampling(true));
  }

  @override
  void releaseBackdrop() {
    if (_backdropConsumers == 0) return;
    if (--_backdropConsumers == 0 && !_disposed) {
      _backdropDecodeGeneration++;
      unawaited(_setBackdropSampling(false));
    }
  }

  Future<void> _setBackdropSampling(bool enabled) async {
    try {
      final handle = await player.handle;
      // A release can overtake the handle lookup of the matching retain.
      if (_disposed || enabled != (_backdropConsumers > 0)) return;
      await _channel.invokeMethod('VideoOutputManager.SetBackdropSampling', {
        'handle': handle.toString(),
        'enabled': enabled,
        'transfer': _backdropTransfer,
      });
    } on MissingPluginException {
      // An older embedding keeps the consumer's opaque fallback.
    } on PlatformException catch (error) {
      debugPrint('Video backdrop sampling unavailable: $error');
    }
  }

  void _acceptBackdrop(ui.Image image, ui.Rect contentRect, int generation) {
    if (_disposed ||
        _backdropConsumers == 0 ||
        generation != _backdropDecodeGeneration) {
      image.dispose();
      return;
    }
    // A panel may still be painting the image it read during this frame.
    // Keep the replaced copy alive until the one after it arrives.
    _retiredBackdrop?.dispose();
    _retiredBackdrop = backdrop.value;
    _backdropFrame = VideoBackdropFrame(image, contentRect);
    backdrop.value = image;
  }

  Future<void> _onTargetChanged(String value) async {
    if (_disposed || _closing) return;
    try {
      final target = jsonDecode(value);
      final active = _directActive ||
          (_nativeSurfaceSelected &&
              target is Map &&
              target['primaries'] == 'bt.2020' &&
              const {'pq', 'hlg'}.contains(target['gamma']));
      nativeHdrActive.value = active;
      final transfer = _directActive
          ? _directTransfer
          : active
              ? target['gamma'] as String
              : '';
      if (_backdropTransfer != transfer) {
        _backdropTransfer = transfer;
        if (_backdropConsumers > 0) unawaited(_setBackdropSampling(true));
      }
      final summary = target is Map
          ? '${target['primaries']}/${target['gamma']} format=${target['pixelformat']} native=$_nativeSurfaceSelected'
          : 'unavailable';
      if (!kReleaseMode && summary != _lastOutputSummary) {
        debugPrint('Android HDR output: $summary');
        _lastOutputSummary = summary;
      }
    } on FormatException {
      nativeHdrActive.value = false;
    }
  }

  Future<void> _onBeforeDecode() async {
    if (_closing || _disposed) return;
    _preparingOutput = true;
    _outputGeneration++;
    _appliedSurfaceKey = null;
    try {
      await _configureBeforeDecode();
    } finally {
      _preparingOutput = false;
      _surfaceReady = null;
    }
  }

  Future<void> _configureBeforeDecode() async {
    _directActive = false;
    _directAllowed = false;
    _dolbyGpuRecovery = null;
    final tracks =
        await platform.getProperty('track-list', waitForInitialization: false);
    Object? decoded;
    try {
      decoded = jsonDecode(tracks);
    } on FormatException {
      // Missing track metadata keeps the user's configured output.
    }
    if (androidTracksUseRawDolbyGpu(decoded)) {
      _dolbyGpuRecovery = AndroidDolbyGpuRecovery();
    }
    _limitSurfaceToDisplay =
        androidTracksHaveHdr(decoded) && androidTracksExceedCopyBudget(decoded);
    androidNativeSurface.value = _nativeHdrSupported &&
        !_nativeSurfaceFailed &&
        androidTracksHaveHdr(decoded);
    _fileVideoOutput = androidVideoOutputForTracks(configuration.vo!, decoded,
        nativeHdr: _nativeHdrSupported);
    final currentDecoder =
        await platform.getProperty('hwdec', waitForInitialization: false);
    _configuredDecoder = currentDecoder;
    // Keep mpv GPU rendering as the default after the sample-library comparison.
    // Native decoder presentation remains opt-in for future device issues,
    // without disabling HDR surfaces, hardware decoding or mpv processing.
    if (const bool.fromEnvironment('BOTA_ANDROID_DIRECT_OUTPUT',
            defaultValue: false) &&
        _supportsDirectOutput &&
        _nativeHdrSupported &&
        !_nativeSurfaceFailed &&
        decoded is List) {
      Future<String> value(String key) =>
          platform.getProperty(key, waitForInitialization: false);
      var customProcessing = false;
      for (final key in [
        'brightness',
        'contrast',
        'saturation',
        'gamma',
        'hue',
        'sub-hdr-peak',
        'image-subs-hdr-peak',
        'secondary-sub-hdr-peak',
        'secondary-image-subs-hdr-peak'
      ]) {
        final configured = await value(key);
        if (configured.isNotEmpty &&
            androidDirectOutputNeedsRenderer(key, configured)) {
          customProcessing = true;
          break;
        }
      }
      if (!customProcessing &&
          androidDirectOutputEligible(
              decoder: currentDecoder,
              tracks: decoded,
              hdrHint: await value('target-colorspace-hint'),
              filters: await value('vf'),
              shaders: await value('glsl-shaders'),
              deinterlace: await value('deinterlace'))) {
        final track = decoded
            .cast<Map>()
            .firstWhere((t) => t['type'] == 'video' && t['selected'] == true);
        final adjusted = <String, Object?>{...track.cast<String, Object?>()};
        _directAllowed = await _channel.invokeMethod<bool>(
                'Utils.SupportsNativeVideo', adjusted) ??
            false;
        _directTransfer = track['demux-gamma'] == 'hlg' ? 'hlg' : 'pq';
      }
    }
    final decoder = androidHardwareDecoderForTracks(
      currentDecoder,
      configuration.vo!,
      decoded,
      nativeHdr: _nativeHdrSupported,
    );
    if (decoder != currentDecoder) {
      await setProperty('file-local-options/hwdec', decoder);
    }
    // Demux dimensions also prepare ordinary SDR textures before decoding.
    // A temporary null VO has no hardware device and can exhaust fallback
    // candidates before the real surface becomes available.
    if (decoded is List) {
      Map? track;
      for (final candidate in decoded) {
        if (candidate is Map &&
            candidate['type'] == 'video' &&
            candidate['selected'] == true) {
          track = candidate;
          break;
        }
      }
      final w = track?['demux-w'], h = track?['demux-h'];
      if (w is num && h is num && w > 0 && h > 0) {
        final views = ui.PlatformDispatcher.instance.views;
        final display = views.isEmpty ? Size.zero : views.first.display.size;
        final size = androidSurfaceSize(w.toInt(), h.toInt(), display,
            highFrameRate: _limitSurfaceToDisplay);
        _surfaceReady = Completer<void>();
        await _channel.invokeMethod('VideoOutputManager.SetSurfaceSize', {
          'handle': '${await player.handle}',
          'width': '${size.width.toInt()}',
          'height': '${size.height.toInt()}',
        });
        // HDR -> SDR must also wait until the outgoing native view has
        // detached. Its Surface can otherwise be destroyed during GPU setup.
        if (!_requestedSurfaceReady) {
          await _surfaceReady!.future
              .timeout(const Duration(milliseconds: 1200), onTimeout: () {});
        }
      }
    }
    if (_closing || _disposed) return;
    if ((wid.value ?? 0) != 0) {
      final direct =
          _directAllowed && _nativeSurfaceSelected && _subtitleWid != 0;
      final output = direct ? 'mediacodec_embed' : _fileVideoOutput!;
      await setProperty('vo', 'null');
      await setProperty('android-surface-size',
          '${rect.value?.width.toInt() ?? 1}x${rect.value?.height.toInt() ?? 1}');
      await setProperty('wid', '${wid.value}');
      if (_nativeHdrSupported) {
        await setProperty('android-hdr-capabilities',
            _nativeSurfaceSelected ? '$_surfaceHdrCapabilities' : '0');
      }
      if (_supportsDirectOutput) {
        await setProperty(
            'android-subtitle-wid', direct ? '$_subtitleWid' : '0');
      }
      await setProperty(
          'file-local-options/hwdec', direct ? 'mediacodec' : decoder);
      _directActive = direct;
      await setProperty('file-local-options/vo', output);
      _appliedSurfaceKey = _surfaceKey(output);
      if (direct) {
        nativeHdrActive.value = true;
        _backdropTransfer = _directTransfer;
      }
    }
  }

  Future<void> _onUnload() async {
    _outputGeneration++;
    _dolbyGpuRecovery = null;
    _appliedSurfaceKey = null;
    _directAllowed = false;
    _directActive = false;
    _fileVideoOutput = null;
    _limitSurfaceToDisplay = false;
    nativeHdrActive.value = false;
    _backdropTransfer = '';
    if (_backdropConsumers > 0) unawaited(_setBackdropSampling(true));
  }

  /// Listener for updating the --wid property.
  Future<void> widListener() {
    if (_preparingOutput || _disposed || _closing) return Future<void>.value();
    final generation = _outputGeneration;
    return lock.synchronized(() async {
      bool stale() =>
          _disposed ||
          _closing ||
          _preparingOutput ||
          generation != _outputGeneration;
      if (stale()) return;
      final width = rect.value?.width.toInt() ?? 1;
      final height = rect.value?.height.toInt() ?? 1;
      final androidSurfaceSizeValue = [width, height].join('x');
      final widValue = wid.value?.toString() ?? '0';
      // When --wid is 0, vo=null is required to avoid SIGSEGV.
      final wasDirect = _directActive;
      final direct = widValue != '0' &&
          _directAllowed &&
          _nativeSurfaceSelected &&
          _subtitleWid != 0;
      final voValue = widValue == '0'
          ? 'null'
          : direct
              ? 'mediacodec_embed'
              : (_fileVideoOutput ?? configuration.vo!);
      final surfaceKey = _surfaceKey(voValue);
      if (surfaceKey == _appliedSurfaceKey) return;
      _directActive = direct;
      if (!kReleaseMode && direct != wasDirect) {
        debugPrint(direct
            ? 'Android video: native decoder surface with mpv subtitles'
            : 'Android video: mpv GPU renderer');
      }
      final selectedVideo = player.state.track.video.id;
      final vidValue = widValue == '0'
          ? 'no'
          : selectedVideo == 'no'
              ? 'auto'
              : selectedVideo;
      // Direct output needs a decoder bound to this exact Surface. Suspend
      // its video track while replacing the VO/device so an intermediate
      // vo=null cannot prematurely exhaust hardware fallback candidates.
      if (direct || wasDirect) {
        await platform.setPropertyAsync('vid', 'no',
            waitForInitialization: false);
      }
      // It is important to re-initialize --vo after --android-surface-size.
      if (stale()) return;
      await platform.setPropertyAsync('vo', 'null',
          waitForInitialization: false);
      if (stale()) return;
      await setProperties(
        {
          // ORDER IS IMPORTANT.
          'android-surface-size': androidSurfaceSizeValue,
          'wid': widValue,
          if (_supportsDirectOutput)
            'android-subtitle-wid': direct ? '$_subtitleWid' : '0',
          if (direct || wasDirect)
            'file-local-options/hwdec':
                direct ? 'mediacodec' : _configuredDecoder,
          if (_nativeHdrSupported)
            'android-hdr-capabilities':
                _nativeSurfaceSelected ? '$_surfaceHdrCapabilities' : '0',
          'vo': voValue,
          // It is important to re-initialize --vid in-case of --vo=mediacodec_embed.
          // Not doing so causes error "Could not open codec." & video never gets rendered.
          if (configuration.vo == 'mediacodec_embed' || direct || wasDirect)
            'vid': vidValue,
        },
        asynchronous: true,
        isCurrent: () => !stale(),
      );
      // Instead of seeking to the start (Duration.zero), seek to the current playback position
      // without jumping the user to the start of the media.
      if (stale()) return;
      _appliedSurfaceKey = surfaceKey;
      final currentPosition = player.state.position;
      await platform.command([
        'seek',
        '${currentPosition.inMilliseconds / 1000}',
        'absolute+exact'
      ], waitForInitialization: false);
      if (direct) nativeHdrActive.value = true;
      if (direct && _backdropTransfer != _directTransfer) {
        _backdropTransfer = _directTransfer;
        if (_backdropConsumers > 0) unawaited(_setBackdropSampling(true));
      }
    });
  }

  /// [StreamSubscription] for listening to video [Rect].
  StreamSubscription<VideoParams>? videoParamsSubscription;

  /// {@macro android_video_controller}
  AndroidVideoController._(
    super.player,
    super.configuration,
  ) {
    wid.addListener(widListener);
    platform.onBeforeDecodeHooks.add(_onBeforeDecode);
    platform.onUnloadHooks.add(_onUnload);
    platform.beforePropertySet.add(_beforePropertySet);
    platform.beforeCommand.add(_beforeCommand);
    platform.beforeScreenshot.add(_leaveDirectOutput);
    videoParamsSubscription = player.stream.videoParams.listen(
      (event) => lock.synchronized(() async {
        if (_disposed || _closing) return;
        final int sourceWidth;
        final int sourceHeight;
        if (event.rotate == 0 || event.rotate == 180) {
          sourceWidth = event.dw ?? 0;
          sourceHeight = event.dh ?? 0;
        } else {
          // width & height are swapped for 90 or 270 degrees rotation.
          sourceWidth = event.dh ?? 0;
          sourceHeight = event.dw ?? 0;
        }
        final views = ui.PlatformDispatcher.instance.views;
        final display = views.isEmpty ? null : views.first.display.size;
        final surface = display == null
            ? null
            : androidSurfaceSize(sourceWidth, sourceHeight, display,
                highFrameRate: _limitSurfaceToDisplay);
        final width = surface?.width.toInt() ?? sourceWidth;
        final height = surface?.height.toInt() ?? sourceHeight;

        final isZero = width == 0 || height == 0;
        final isSame = width == rect.value?.width.toInt() &&
            height == rect.value?.height.toInt();
        if (isZero || isSame) {
          return;
        }

        final handle = await player.handle;

        await _channel.invokeMethod(
          'VideoOutputManager.SetSurfaceSize',
          {
            'handle': handle.toString(),
            'width': width.toString(),
            'height': height.toString(),
          },
        );

        if (_closing || _disposed) return;
        rect.value = Rect.fromLTWH(
          0.0,
          0.0,
          width.toDouble(),
          height.toDouble(),
        );

        if (!waitUntilFirstFrameRenderedCompleter.isCompleted) {
          waitUntilFirstFrameRenderedCompleter.complete();
        }
      }),
    );
  }

  /// {@macro android_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) async {
    Future<String> getDefaultHwdec() async {
      // Enforce software rendering in emulators.
      bool hw = configuration.enableHardwareAcceleration;
      final bool isEmulator = await _channel.invokeMethod('Utils.IsEmulator');
      if (isEmulator) {
        hw = false;
        debugPrint('media_kit: Emulator detected.');
        debugPrint('media_kit: Enforcing S/W rendering.');
      }
      return hw ? 'auto-safe' : 'no';
    }

    // Update [configuration] to have default values.
    configuration = configuration.copyWith(
      vo: configuration.vo ??
          (configuration.renderBackend == 'gpu-next' ? 'gpu-next' : 'gpu'),
      hwdec: configuration.hwdec ?? await getDefaultHwdec(),
    );

    // Retrieve the native handle of the [Player].
    final handle = await player.handle;
    // Return the existing [VideoController] if it's already created.
    if (_controllers.containsKey(handle)) {
      return _controllers[handle]!;
    }

    // In case no video-decoders are found, this means media_kit_libs_***_audio is being used.
    // Thus, --vid=no is required to prevent libmpv from trying to decode video (otherwise bad things may happen).
    //
    // Search for common H264 decoder to check if video support is available.
    final decoders = await queryDecoders(handle);
    if (!decoders.contains('h264')) {
      throw UnsupportedError(
        '[VideoController] is not available.'
        ' '
        'Please use media_kit_libs_***_video instead of media_kit_libs_***_audio.',
      );
    }

    // Creation:
    final controller = AndroidVideoController._(
      player,
      configuration,
    );

    // Register [_dispose] for execution upon [Player.dispose].
    player.platform?.release.add(controller._dispose);

    // Store the [VideoController] in the [_controllers].
    _controllers[handle] = controller;
    if (configuration.androidNativeHdr) {
      try {
        final option = await controller.platform.getProperty(
            'option-info/android-hdr-capabilities',
            waitForInitialization: false);
        final caps =
            await _channel.invokeMethod<int>('Utils.HdrCapabilities') ?? 0;
        controller._nativeHdrSupported = option.isNotEmpty && caps != 0;
        controller._supportsDirectOutput = (await controller.platform
                .getProperty('option-info/android-subtitle-wid',
                    waitForInitialization: false))
            .isNotEmpty;
      } catch (_) {
        // An older plugin or library cannot accept HDR buffers safely.
      }
    }

    await _channel.invokeMethod(
      'VideoOutputManager.Create',
      {
        'handle': handle.toString(),
      },
    );

    await controller.setProperties(
      {
        // It is necessary to set vo=null here to avoid SIGSEGV, --wid must be assigned before vo=gpu is set.
        'vo': 'null',
        'hwdec': configuration.hwdec!,
        'vid': 'auto',
        'opengl-es': 'yes',
        'force-window': 'yes',
        'gpu-context': 'android',
        if (controller._nativeHdrSupported) 'android-hdr-capabilities': '0',
        'sub-use-margins': 'no',
        'sub-font-provider': 'none',
        'sub-scale-with-window': 'yes',
        'hwdec-codecs': 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1',
      },
    );

    if (controller._nativeHdrSupported) {
      await controller.platform.observeProperty(
          'video-target-params', controller._onTargetChanged,
          waitForInitialization: false);
      controller._observesTarget = true;
    }
    // Raw Dolby GPU imports can also be used while mapping to an SDR display.
    controller._renderLogSubscription = player.stream.log.listen((entry) {
      final generation = controller._outputGeneration;
      scheduleMicrotask(
          () => unawaited(controller._onRenderLog(entry, generation)));
    });
    // Return the [PlatformVideoController].
    return controller;
  }

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  @override
  Future<void> setSize({
    int? width,
    int? height,
  }) {
    throw UnsupportedError(
      '[AndroidVideoController.setSize] is not available on Android',
    );
  }

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() async {
    _disposed = true;
    if (_observesTarget && !platform.disposed) {
      await platform.unobserveProperty('video-target-params',
          waitForInitialization: false);
    }
    platform.onBeforeDecodeHooks.remove(_onBeforeDecode);
    platform.onUnloadHooks.remove(_onUnload);
    platform.beforePropertySet.remove(_beforePropertySet);
    platform.beforeCommand.remove(_beforeCommand);
    platform.beforeScreenshot.remove(_leaveDirectOutput);
    wid.removeListener(widListener);
    wid.dispose();
    await videoParamsSubscription?.cancel();
    await _renderLogSubscription?.cancel();
    final handle = await player.handle;
    _controllers.remove(handle);
    _backdropConsumers = 0;
    _backdropDecodeGeneration++;
    _backdropFrame = null;
    _retiredBackdrop?.dispose();
    _retiredBackdrop = null;
    await _channel.invokeMethod(
      'VideoOutputManager.Dispose',
      {
        'handle': handle.toString(),
      },
    );
    super.dispose();
  }

  /// Currently created [AndroidVideoController]s.
  static final _controllers = HashMap<int, AndroidVideoController>();

  /// Accepts legacy copies and copies with a versioned picture/gutter header.
  static void _onBackdropMessage(ByteData message) {
    final copy = VideoBackdropMessage.parse(message);
    if (copy == null) return;
    final controller = _controllers[copy.handle];
    if (controller == null ||
        controller._disposed ||
        controller._backdropConsumers == 0) {
      return;
    }
    // The platform buffer is only valid during this call.
    final pixels = Uint8List.fromList(copy.pixels);
    final generation = ++controller._backdropDecodeGeneration;
    ui.decodeImageFromPixels(
        pixels,
        copy.width,
        copy.height,
        ui.PixelFormat.rgba8888,
        (image) =>
            controller._acceptBackdrop(image, copy.contentRect, generation));
  }

  static bool _backdropChannelReady = false;

  static void _ensureBackdropChannel() {
    if (_backdropChannelReady) return;
    _backdropChannelReady = true;
    const BasicMessageChannel<ByteData?>(
            'com.alexmercerind/media_kit_video/backdrop', BinaryCodec())
        .setMessageHandler((message) async {
      try {
        if (message != null) _onBackdropMessage(message);
      } catch (error, stack) {
        debugPrint('Video backdrop message rejected: $error\n$stack');
      }
      return null;
    });
  }

  /// [MethodChannel] for invoking platform specific native implementation.
  static final _channel = const MethodChannel(
      'com.alexmercerind/media_kit_video')
    ..setMethodCallHandler(
      (MethodCall call) async {
        try {
          debugPrint(call.method.toString());
          debugPrint(call.arguments.toString());
          switch (call.method) {
            case 'VideoOutput.Resize':
              {
                // Notify about updated texture ID & [Rect].
                final int handle = call.arguments['handle'];
                final Rect rect = Rect.fromLTWH(
                  call.arguments['rect']['left'] * 1.0,
                  call.arguments['rect']['top'] * 1.0,
                  call.arguments['rect']['width'] * 1.0,
                  call.arguments['rect']['height'] * 1.0,
                );
                final int id = call.arguments['id'];
                final int wid = call.arguments['wid'];
                final controller = _controllers[handle];
                if (controller == null ||
                    controller._disposed ||
                    controller._closing) {
                  break;
                }
                final caps = call.arguments['hdrCapabilities'] as int? ?? 0;
                final native = call.arguments['nativeSurface'] == true;
                final subtitleWid = call.arguments['subtitleWid'] as int? ?? 0;
                final changed = caps != controller._surfaceHdrCapabilities ||
                    native != controller._nativeSurfaceSelected ||
                    subtitleWid != controller._subtitleWid;
                controller._subtitleWid = subtitleWid;
                controller._surfaceHdrCapabilities = caps;
                controller._nativeSurfaceSelected = native;
                controller.rect.value = rect;
                controller.id.value = id;
                if (wid == controller.wid.value && changed) {
                  unawaited(controller.widListener());
                } else {
                  controller.wid.value = wid;
                }
                if (controller._preparingOutput &&
                    controller._requestedSurfaceReady) {
                  final ready = controller._surfaceReady;
                  if (ready != null && !ready.isCompleted) ready.complete();
                }
                break;
              }
            case 'VideoOutput.WaitUntilFirstFrameRenderedNotify':
              {
                // Notify about updated texture ID & [Rect].
                final int handle = call.arguments['handle'];
                debugPrint(handle.toString());
                // Notify about the first frame being rendered.
                final completer =
                    _controllers[handle]?.waitUntilFirstFrameRenderedCompleter;
                if (!(completer?.isCompleted ?? true)) {
                  completer?.complete();
                }
                break;
              }
            default:
              {
                break;
              }
          }
        } catch (exception, stacktrace) {
          debugPrint(exception.toString());
          debugPrint(stacktrace.toString());
        }
      },
    );
}

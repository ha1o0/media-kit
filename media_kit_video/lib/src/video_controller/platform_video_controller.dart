/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/video_controller/video_controller.dart';

/// {@template platform_video_controller}
///
/// PlatformVideoController
/// -----------------------
///
/// This class provides the interface for platform specific [VideoController] implementations.
/// The platform specific implementations are expected to implement the methods accordingly.
///
/// The subclasses are then used in composition with the [VideoController] class, based on the platform the application is running on.
///
/// {@endtemplate}
abstract class PlatformVideoController {
  /// The [Player] instance associated with this instance.
  final Player player;

  /// User defined configuration for [VideoController].
  final VideoControllerConfiguration configuration;

  /// Whether this controller presents video through a native top-level window
  /// instead of a Flutter texture.
  bool get usesNativeWindow => false;

  /// Texture ID of the video output, registered with Flutter engine by the native implementation.
  final ValueNotifier<int?> id = ValueNotifier<int?>(null);

  /// [Rect] of the video output, received from the native implementation.
  final ValueNotifier<Rect?> rect = ValueNotifier<Rect?>(null);

  /// A direct Android SurfaceView is required before HDR buffers are produced.
  final ValueNotifier<bool> androidNativeSurface = ValueNotifier<bool>(false);

  /// Actual native output, after display capability and source/target negotiation.
  final ValueNotifier<bool> nativeHdrActive = ValueNotifier<bool>(false);

  /// A small, already blurred copy of the composited video, refreshed a few
  /// times per second while [retainBackdrop] is held. Null until a platform
  /// that provides one (Android) has delivered its first copy.
  final ValueNotifier<ui.Image?> backdrop = ValueNotifier<ui.Image?>(null);

  /// Starts backdrop copies for one more consumer. Balanced by
  /// [releaseBackdrop]; platforms without a backdrop ignore both.
  void retainBackdrop() {}

  void releaseBackdrop() {}

  /// {@macro platform_video_controller}
  PlatformVideoController(
    this.player,
    this.configuration,
  );

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  Future<void> setSize({
    int? width,
    int? height,
  });

  /// Updates the native video plane bounds in Flutter logical coordinates.
  /// Texture-backed implementations intentionally ignore this operation.
  Future<void> setNativeWindowBounds(Rect bounds, {required bool visible}) {
    return Future<void>.value();
  }

  /// Applies Flutter's fit semantics to a native video window.
  /// Texture-backed implementations intentionally ignore this operation.
  Future<void> setNativeWindowFit(BoxFit fit) {
    return Future<void>.value();
  }

  /// A [Future] that completes when the first video frame has been rendered.
  Future<void> get waitUntilFirstFrameRendered =>
      waitUntilFirstFrameRenderedCompleter.future;

  /// [Completer] used to signal the decoding & rendering of the first video frame.
  /// Use [waitUntilFirstFrameRendered] to wait for the first frame to be rendered.
  @protected
  final waitUntilFirstFrameRenderedCompleter = Completer<void>();

  void dispose() {
    id.dispose();
    rect.dispose();
    nativeHdrActive.dispose();
    androidNativeSurface.dispose();
    backdrop.value?.dispose();
    backdrop.dispose();
  }
}

/// {@template video_controller_configuration}
///
/// VideoControllerConfiguration
/// ----------------------------
/// Configurable options for customizing the [VideoController] behavior.
///
/// {@endtemplate}
class VideoControllerConfiguration {
  /// Sets the [`--vo`](https://mpv.io/manual/stable/#options-vo) property on native backend.
  ///
  /// Default: Platform specific.
  /// * Windows, GNU/Linux, macOS & iOS: `libmpv`
  /// * Android: `gpu`
  final String? vo;

  /// Sets the [`--hwdec`](https://mpv.io/manual/stable/#options-hwdec) property on native backend.
  ///
  /// Default: Platform specific.
  /// * Windows, GNU/Linux, macOS & iOS : `auto`
  /// * Android: `auto-safe`
  final String? hwdec;

  /// The scale for the video output.
  /// This may be used for performance reasons. Specifying this option will cause [width] & [height] to be ignored.
  ///
  /// Default: `1.0`
  final double scale;

  /// The fixed width for the video output.
  /// This may be used for performance reasons.
  ///
  /// Default: `null`
  final int? width;

  /// The fixed height for the video output.
  /// This may be used for performance reasons.
  ///
  /// Default: `null`
  final int? height;

  /// Whether to enable hardware acceleration.
  ///
  /// DO NOT DISABLE THIS OPTION MEANINGLESSLY.
  /// THE BATTERY WILL DRAIN, THE DEVICE MAY HEAT UP & CPU USAGE WILL BE HIGH.
  ///
  /// Default: `true`
  final bool enableHardwareAcceleration;

  /// Selects the native libmpv render backend when the platform implementation
  /// supports it.
  ///
  /// Default: Platform specific.
  final String? renderBackend;

  /// Presents video through a native window on supported desktop platforms.
  ///
  /// Default: `false`.
  final bool useNativeWindow;

  /// Stable key used by the Windows plugin to own a pre-created native window.
  final int? nativeWindowKey;

  /// HWND allocated before libmpv initialization.
  final Future<int>? nativeWindowHandle;

  /// Whether to attach `android.view.Surface` after video parameters are known.
  ///
  /// Default:
  /// * [vo] == gpu : `true`
  /// * [vo] != gpu : `false`
  final bool? androidAttachSurfaceAfterVideoParameters;

  /// Negotiate native Android HDR while keeping mpv GPU subtitle rendering.
  /// Unsupported displays or native libraries retain the SDR texture path.
  final bool androidNativeHdr;

  /// {@macro video_controller_configuration}
  const VideoControllerConfiguration({
    this.vo,
    this.hwdec,
    this.width,
    this.height,
    this.scale = 1.0,
    this.enableHardwareAcceleration = true,
    this.renderBackend,
    this.useNativeWindow = false,
    this.nativeWindowKey,
    this.nativeWindowHandle,
    this.androidAttachSurfaceAfterVideoParameters,
    this.androidNativeHdr = false,
  });

  /// Returns a copy of this class with the given fields replaced by the new values.
  VideoControllerConfiguration copyWith({
    String? vo,
    String? hwdec,
    double? scale,
    int? width,
    int? height,
    bool? enableHardwareAcceleration,
    String? renderBackend,
    bool? useNativeWindow,
    int? nativeWindowKey,
    Future<int>? nativeWindowHandle,
    bool? androidAttachSurfaceAfterVideoParameters,
    bool? androidNativeHdr,
  }) =>
      VideoControllerConfiguration(
        vo: vo ?? this.vo,
        androidNativeHdr: androidNativeHdr ?? this.androidNativeHdr,
        hwdec: hwdec ?? this.hwdec,
        scale: scale ?? this.scale,
        width: width ?? this.width,
        height: height ?? this.height,
        enableHardwareAcceleration:
            enableHardwareAcceleration ?? this.enableHardwareAcceleration,
        renderBackend: renderBackend ?? this.renderBackend,
        useNativeWindow: useNativeWindow ?? this.useNativeWindow,
        nativeWindowKey: nativeWindowKey ?? this.nativeWindowKey,
        nativeWindowHandle: nativeWindowHandle ?? this.nativeWindowHandle,
        androidAttachSurfaceAfterVideoParameters:
            androidAttachSurfaceAfterVideoParameters ??
                this.androidAttachSurfaceAfterVideoParameters,
      );
}

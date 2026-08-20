/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart';

import 'package:media_kit_video/src/subtitle/subtitle_view.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as media_kit_video_controls;
import 'package:media_kit_video/src/utils/dispose_safe_notifer.dart';

import 'package:media_kit_video/src/utils/wakelock.dart';
import 'package:media_kit_video/src/video_view_parameters.dart';
import 'package:media_kit_video/src/video_controller/video_controller.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

/// {@template video}
///
/// Video
/// -----
/// [Video] widget is used to display video output.
///
/// Use [VideoController] to initialize & handle the video rendering.
///
/// **Example:**
///
/// ```dart
/// class MyScreen extends StatefulWidget {
///   const MyScreen({Key? key}) : super(key: key);
///   @override
///   State<MyScreen> createState() => MyScreenState();
/// }
///
/// class MyScreenState extends State<MyScreen> {
///   late final player = Player();
///   late final controller = VideoController(player);
///
///   @override
///   void initState() {
///     super.initState();
///     player.open(Media('https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4'));
///   }
///
///   @override
///   void dispose() {
///     player.dispose();
///     super.dispose();
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///       body: Video(
///         controller: controller,
///       ),
///     );
///   }
/// }
/// ```
///
/// {@endtemplate}
class Video extends StatefulWidget {
  /// The [VideoController] reference to control this [Video] output.
  final VideoController controller;

  /// Width of this viewport.
  final double? width;

  /// Height of this viewport.
  final double? height;

  /// Fit of the viewport.
  final BoxFit fit;

  /// Background color to fill the video background.
  final Color fill;

  /// Alignment of the viewport.
  final Alignment alignment;

  /// Preferred aspect ratio of the viewport.
  final double? aspectRatio;

  /// Filter quality of the [Texture] widget displaying the video output.
  final FilterQuality filterQuality;

  /// Visual rotation applied to the rendered video frame only.
  final int visualRotation;

  /// Whether to mirror the rendered video frame horizontally.
  final bool visualMirror;

  /// Video controls builder.
  final VideoControlsBuilder? controls;

  /// Whether to acquire wake lock while playing the video.
  final bool wakelock;

  /// Whether to pause the video when application enters background mode.
  final bool pauseUponEnteringBackgroundMode;

  /// Whether to resume the video when application enters foreground mode.
  ///
  /// This attribute is only applicable if [pauseUponEnteringBackgroundMode] is `true`.
  ///
  final bool resumeUponEnteringForegroundMode;

  /// The configuration for subtitles e.g. [TextStyle] & padding etc.
  final SubtitleViewConfiguration subtitleViewConfiguration;

  /// The callback invoked when the [Video] enters fullscreen.
  final Future<void> Function() onEnterFullscreen;

  /// The callback invoked when the [Video] exits fullscreen.
  final Future<void> Function() onExitFullscreen;

  /// FocusNode for keyboard input.
  final FocusNode? focusNode;

  /// Whether the video plane is rendered by Flutter's [Texture] widget.
  /// Controls, subtitles and lifecycle behavior remain active when disabled.
  final bool renderTexture;

  /// Whether a native video window should remain visible while this widget is
  /// retained in an offstage page. Fullscreen routes set this explicitly.
  final bool nativeWindowVisible;

  /// {@macro video}
  const Video({
    super.key,
    required this.controller,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.fill = const Color(0xFF000000),
    this.alignment = Alignment.center,
    this.aspectRatio,
    this.filterQuality = FilterQuality.low,
    this.visualRotation = 0,
    this.visualMirror = false,
    this.controls = media_kit_video_controls.AdaptiveVideoControls,
    this.wakelock = true,
    this.pauseUponEnteringBackgroundMode = true,
    this.resumeUponEnteringForegroundMode = false,
    this.subtitleViewConfiguration = const SubtitleViewConfiguration(),
    this.onEnterFullscreen = defaultEnterNativeFullscreen,
    this.onExitFullscreen = defaultExitNativeFullscreen,
    this.focusNode,
    this.renderTexture = true,
    this.nativeWindowVisible = true,
  });

  @override
  State<Video> createState() => VideoState();
}

class VideoState extends State<Video> with WidgetsBindingObserver {
  late final _contextNotifier = DisposeSafeNotifier<BuildContext?>(null);
  late ValueNotifier<VideoViewParameters> videoViewParametersNotifier;
  late bool _disposeNotifiers;
  final _subtitleViewKey = GlobalKey<SubtitleViewState>();
  final _nativeWindowViewportKey = GlobalKey();
  final _wakelock = Wakelock();
  final _subscriptions = <StreamSubscription>[];
  late int? _width = widget.controller.player.state.width;
  late int? _height = widget.controller.player.state.height;
  late bool _visible =
      !widget.renderTexture || ((_width ?? 0) > 0 && (_height ?? 0) > 0);

  bool _pauseDueToPauseUponEnteringBackgroundMode = false;
  bool _nativeWindowSyncScheduled = false;
  BoxFit? _lastNativeWindowFit;
  bool _tickerModeEnabled = true;
  // The source Video remains mounted while media-kit's fullscreen route is
  // pushed.  A native HWND is a single shared resource, so the source must
  // stop publishing its old viewport while the fullscreen copy owns it.
  bool _nativeFullscreenRouteActive = false;
  VideoState? _nativeFullscreenParent;
  final ValueNotifier<int> _nativeFullscreenOwnershipRevision =
      ValueNotifier<int>(0);
  Rect? _lastNativeWindowBounds;
  bool? _lastNativeWindowVisible;
  bool _platformControllerListenerAttached = false;
  // Public API:
  bool isFullscreen() {
    final context = _contextNotifier.value;
    if (context == null || !context.mounted) return false;
    return media_kit_video_controls.isFullscreen(context);
  }

  Future<void> enterFullscreen() async {
    final context = _contextNotifier.value;
    if (context == null || !context.mounted) return;
    await media_kit_video_controls.enterFullscreen(context);
  }

  Future<void> exitFullscreen() async {
    final context = _contextNotifier.value;
    if (context == null || !context.mounted) return;
    await media_kit_video_controls.exitFullscreen(context);
  }

  Future<void> toggleFullscreen() async {
    final context = _contextNotifier.value;
    if (context == null || !context.mounted) return;
    await media_kit_video_controls.toggleFullscreen(context);
  }

  void setSubtitleViewPadding(
    EdgeInsets padding, {
    Duration duration = const Duration(milliseconds: 100),
  }) {
    return _subtitleViewKey.currentState?.setPadding(
      padding,
      duration: duration,
    );
  }

  void update({
    double? width,
    double? height,
    BoxFit? fit,
    Color? fill,
    Alignment? alignment,
    double? aspectRatio,
    FilterQuality? filterQuality,
    int? visualRotation,
    bool? visualMirror,
    VideoControlsBuilder? controls,
    SubtitleViewConfiguration? subtitleViewConfiguration,
    FocusNode? focusNode,
  }) {
    videoViewParametersNotifier.value =
        videoViewParametersNotifier.value.copyWith(
      width: width,
      height: height,
      fit: fit,
      fill: fill,
      alignment: alignment,
      aspectRatio: aspectRatio,
      filterQuality: filterQuality,
      visualRotation: visualRotation,
      visualMirror: visualMirror,
      controls: controls,
      subtitleViewConfiguration: subtitleViewConfiguration,
      focusNode: focusNode,
    );
  }

  @override
  void didChangeDependencies() {
    final tickerModeEnabled = TickerMode.valuesOf(context).enabled;
    final tickerModeChanged = _tickerModeEnabled != tickerModeEnabled;
    _tickerModeEnabled = tickerModeEnabled;
    videoViewParametersNotifier =
        media_kit_video_controls.VideoStateInheritedWidget.maybeOf(
              context,
            )?.videoViewParametersNotifier ??
            ValueNotifier<VideoViewParameters>(
              VideoViewParameters(
                width: widget.width,
                height: widget.height,
                fit: widget.fit,
                fill: widget.fill,
                alignment: widget.alignment,
                aspectRatio: widget.aspectRatio,
                filterQuality: widget.filterQuality,
                visualRotation: widget.visualRotation,
                visualMirror: widget.visualMirror,
                controls: widget.controls,
                subtitleViewConfiguration: widget.subtitleViewConfiguration,
                focusNode: widget.focusNode,
              ),
            );
    _disposeNotifiers =
        media_kit_video_controls.VideoStateInheritedWidget.maybeOf(
              context,
            )?.disposeNotifiers ??
            true;
    final nativeFullscreenParent = !widget.renderTexture
        ? media_kit_video_controls.FullscreenInheritedWidget.maybeOf(context)
            ?.parent
        : null;
    if (!identical(_nativeFullscreenParent, nativeFullscreenParent)) {
      _nativeFullscreenParent?._nativeFullscreenOwnershipRevision
          .removeListener(_handleNativeFullscreenOwnershipChanged);
      _nativeFullscreenParent = nativeFullscreenParent;
      _nativeFullscreenParent?._nativeFullscreenOwnershipRevision
          .addListener(_handleNativeFullscreenOwnershipChanged);
    }
    super.didChangeDependencies();
    if (!widget.renderTexture && tickerModeChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _forceNativeWindowSync();
      });
    }
  }

  @override
  void didUpdateWidget(Video oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(widget.controller, oldWidget.controller)) {
      _detachPlatformControllerListener(oldWidget.controller);
      _attachPlatformControllerListener();
      _lastNativeWindowFit = null;
      _handlePlatformControllerChanged();
    } else if (!widget.renderTexture && widget.fit != oldWidget.fit) {
      _syncNativeWindowFit(widget.fit);
    }
    if (widget.renderTexture != oldWidget.renderTexture) {
      if (widget.renderTexture) {
        _detachPlatformControllerListener(widget.controller);
      } else {
        _attachPlatformControllerListener();
        _handlePlatformControllerChanged();
      }
    }

    if (widget.renderTexture != oldWidget.renderTexture ||
        widget.nativeWindowVisible != oldWidget.nativeWindowVisible) {
      _visible =
          !widget.renderTexture || ((_width ?? 0) > 0 && (_height ?? 0) > 0);
      _lastNativeWindowBounds = null;
      _lastNativeWindowVisible = null;
    }

    final currentParams = videoViewParametersNotifier.value;

    final newParams = currentParams.copyWith(
      width:
          widget.width != oldWidget.width ? widget.width : currentParams.width,
      height: widget.height != oldWidget.height
          ? widget.height
          : currentParams.height,
      fit: widget.fit != oldWidget.fit ? widget.fit : currentParams.fit,
      fill: widget.fill != oldWidget.fill ? widget.fill : currentParams.fill,
      alignment: widget.alignment != oldWidget.alignment
          ? widget.alignment
          : currentParams.alignment,
      aspectRatio: widget.aspectRatio != oldWidget.aspectRatio
          ? widget.aspectRatio
          : currentParams.aspectRatio,
      filterQuality: widget.filterQuality != oldWidget.filterQuality
          ? widget.filterQuality
          : currentParams.filterQuality,
      visualRotation: widget.visualRotation != oldWidget.visualRotation
          ? widget.visualRotation
          : currentParams.visualRotation,
      visualMirror: widget.visualMirror != oldWidget.visualMirror
          ? widget.visualMirror
          : currentParams.visualMirror,
      controls: widget.controls != oldWidget.controls
          ? widget.controls
          : currentParams.controls,
      subtitleViewConfiguration: widget.subtitleViewConfiguration !=
              oldWidget.subtitleViewConfiguration
          ? widget.subtitleViewConfiguration
          : currentParams.subtitleViewConfiguration,
      focusNode: widget.focusNode != oldWidget.focusNode
          ? widget.focusNode
          : currentParams.focusNode,
    );

    if (newParams != currentParams) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || (_disposeNotifiers && _contextNotifier.disposed)) {
          return;
        }
        videoViewParametersNotifier.value = newParams;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.pauseUponEnteringBackgroundMode) {
      if ([
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ].contains(state)) {
        if (widget.controller.player.state.playing) {
          _pauseDueToPauseUponEnteringBackgroundMode = true;
          widget.controller.player.pause();
        }
      } else {
        if (widget.resumeUponEnteringForegroundMode &&
            _pauseDueToPauseUponEnteringBackgroundMode) {
          _pauseDueToPauseUponEnteringBackgroundMode = false;
          widget.controller.player.play();
        }
      }
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachPlatformControllerListener();
    _handlePlatformControllerChanged();
    // --------------------------------------------------
    // Do not show the video frame until width & height are available.
    // Since [ValueNotifier<Rect?>] inside [VideoController] only gets updated by the render loop (i.e. it will not fire when video's width & height are not available etc.), it's important to handle this separately here.
    _subscriptions.addAll(
      [
        widget.controller.player.stream.width.listen(
          (value) {
            _width = value;
            final visible = !widget.renderTexture ||
                ((_width ?? 0) > 0 && (_height ?? 0) > 0);
            if (mounted && _visible != visible) {
              setState(() {
                _visible = visible;
              });
            }
          },
        ),
        widget.controller.player.stream.height.listen(
          (value) {
            _height = value;
            final visible = !widget.renderTexture ||
                ((_width ?? 0) > 0 && (_height ?? 0) > 0);
            if (mounted && _visible != visible) {
              setState(() {
                _visible = visible;
              });
            }
          },
        ),
        if (!widget.renderTexture)
          widget.controller.player.stream.videoParams.listen((value) {
            if ((value.dw ?? value.w ?? 0) > 0 &&
                (value.dh ?? value.h ?? 0) > 0) {
              _forceNativeWindowSync();
            }
          }),
        if (!widget.renderTexture)
          widget.controller.player.stream.playing.listen((value) {
            if (value) {
              _forceNativeWindowSync();
            }
          }),
      ],
    );
    // --------------------------------------------------
    if (widget.wakelock) {
      if (widget.controller.player.state.playing) {
        _wakelock.enable();
      }
      _subscriptions.add(
        widget.controller.player.stream.playing.listen(
          (value) {
            if (value) {
              _wakelock.enable();
            } else {
              _wakelock.disable();
            }
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nativeFullscreenParent?._nativeFullscreenOwnershipRevision
        .removeListener(_handleNativeFullscreenOwnershipChanged);
    _nativeFullscreenOwnershipRevision.dispose();
    _detachPlatformControllerListener(widget.controller);
    _wakelock.disable();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    if (_disposeNotifiers) {
      videoViewParametersNotifier.dispose();
      _contextNotifier.dispose();
      VideoStateInheritedWidgetContextNotifierState.fallback.remove(this);
    }

    super.dispose();
  }

  void _handlePlatformControllerChanged() {
    if (!widget.renderTexture) {
      _syncNativeWindowFit(widget.fit);
    }
  }

  void _attachPlatformControllerListener() {
    if (widget.renderTexture || _platformControllerListenerAttached) return;
    widget.controller.notifier.addListener(_handlePlatformControllerChanged);
    _platformControllerListenerAttached = true;
  }

  void _detachPlatformControllerListener(VideoController controller) {
    if (!_platformControllerListenerAttached) return;
    controller.notifier.removeListener(_handlePlatformControllerChanged);
    _platformControllerListenerAttached = false;
  }

  void _handleNativeFullscreenOwnershipChanged() {
    _forceNativeWindowSync();
  }

  void _syncNativeWindowFit(BoxFit fit) {
    final platform = widget.controller.notifier.value;
    if (platform == null || !platform.usesNativeWindow) return;
    if (_lastNativeWindowFit == fit) return;
    _lastNativeWindowFit = fit;
    unawaited(
      platform.setNativeWindowFit(fit).catchError(
        (Object error, StackTrace stackTrace) {
          _lastNativeWindowFit = null;
          debugPrint(
            'Video: failed to apply native window fit: '
            '$error\n$stackTrace',
          );
        },
      ),
    );
  }

  void refreshView() {}

  /// Transfers native-window layout ownership to/from media-kit's fullscreen
  /// route.  This is intentionally a no-op for Flutter Texture rendering.
  void setNativeFullscreenRouteActive(bool active) {
    if (widget.renderTexture || _nativeFullscreenRouteActive == active) {
      return;
    }
    _nativeFullscreenRouteActive = active;
    _nativeFullscreenOwnershipRevision.value++;
    _forceNativeWindowSync();
  }

  bool get nativeFullscreenRouteActive => _nativeFullscreenRouteActive;

  void _scheduleNativeWindowSync() {
    if (widget.renderTexture || _nativeWindowSyncScheduled) return;
    // The original Video is retained underneath the fullscreen route.  Do
    // not let its stale RenderBox overwrite the fullscreen HWND bounds.
    final fullscreenRoute =
        media_kit_video_controls.FullscreenInheritedWidget.maybeOf(context);
    final ownsNativeFullscreenWindow = fullscreenRoute == null
        ? !_nativeFullscreenRouteActive
        : fullscreenRoute.parent.nativeFullscreenRouteActive;
    if (!ownsNativeFullscreenWindow) {
      return;
    }
    _nativeWindowSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nativeWindowSyncScheduled = false;
      if (!mounted) return;
      final platform = widget.controller.notifier.value;
      final renderObject =
          _nativeWindowViewportKey.currentContext?.findRenderObject();
      if (platform == null ||
          !platform.usesNativeWindow ||
          renderObject is! RenderBox ||
          !renderObject.hasSize) {
        return;
      }

      final origin = renderObject.localToGlobal(Offset.zero);
      final bounds = origin & renderObject.size;
      // TickerMode is disabled for every covered route, including dialogs and
      // the source Video while media-kit's fullscreen Video is being mounted.
      // It therefore cannot represent native-window visibility: hiding here
      // blanks the video under dialogs and can race the fullscreen view. Keep
      // using TickerMode changes to trigger a bounds resync, but let the
      // mounted native view remain visible. Opaque Flutter routes cover it.
      final visible = _visible && widget.nativeWindowVisible;
      if (_lastNativeWindowBounds == bounds &&
          _lastNativeWindowVisible == visible) {
        return;
      }
      _lastNativeWindowBounds = bounds;
      _lastNativeWindowVisible = visible;
      unawaited(
        platform.setNativeWindowBounds(bounds, visible: visible).catchError(
          (Object error, StackTrace stackTrace) {
            debugPrint(
              'Video: failed to update native window bounds: '
              '$error\n$stackTrace',
            );
          },
        ),
      );
    });
  }

  void _forceNativeWindowSync() {
    if (widget.renderTexture || !mounted) return;
    _lastNativeWindowBounds = null;
    _lastNativeWindowVisible = null;
    _scheduleNativeWindowSync();
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _maybeRepaintBoundary({required Widget child}) {
    // This optimization targets the Windows high-refresh Texture path. Keep
    // other platforms on their original layer tree until they are profiled.
    return Platform.isWindows ? RepaintBoundary(child: child) : child;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleNativeWindowSync();
    return media_kit_video_controls.VideoStateInheritedWidget(
      state: this as dynamic,
      contextNotifier: _contextNotifier,
      videoViewParametersNotifier: videoViewParametersNotifier,
      child: ValueListenableBuilder<VideoViewParameters>(
        valueListenable: videoViewParametersNotifier,
        builder: (context, videoViewParameters, _) {
          return Container(
            key: _nativeWindowViewportKey,
            clipBehavior: Clip.none,
            width: videoViewParameters.width,
            height: videoViewParameters.height,
            color: videoViewParameters.fill,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!widget.renderTexture)
                  ValueListenableBuilder<PlatformVideoController?>(
                    valueListenable: widget.controller.notifier,
                    builder: (context, _, __) {
                      _scheduleNativeWindowSync();
                      return const SizedBox.expand();
                    },
                  ),
                // Isolate the video texture into its own compositing layer.
                // Without this boundary, any setState in the controls or
                // subtitle layers forces Flutter to re-rasterize the entire
                // Stack — including the (potentially 4K) video texture — on
                // every frame.  With separate RepaintBoundary layers, only
                // the dirty layer is re-rasterized.
                if (widget.renderTexture)
                  _maybeRepaintBoundary(
                    child: ClipRect(
                      child: FittedBox(
                        fit: videoViewParameters.fit,
                        alignment: videoViewParameters.alignment,
                        child: ValueListenableBuilder<PlatformVideoController?>(
                          valueListenable: widget.controller.notifier,
                          builder: (context, notifier, _) => notifier == null
                              ? const SizedBox.shrink()
                              : ValueListenableBuilder<int?>(
                                  valueListenable: notifier.id,
                                  builder: (context, id, _) {
                                    return ValueListenableBuilder<Rect?>(
                                      valueListenable: notifier.rect,
                                      builder: (context, rect, _) {
                                        if (id != null &&
                                            rect != null &&
                                            _visible) {
                                          final view = SizedBox(
                                            // Apply aspect ratio if provided.
                                            width: videoViewParameters
                                                        .aspectRatio ==
                                                    null
                                                ? rect.width
                                                : rect.height *
                                                    videoViewParameters
                                                        .aspectRatio!,
                                            height: rect.height,
                                            child: Stack(
                                              children: [
                                                const SizedBox(),
                                                Positioned.fill(
                                                  child: Texture(
                                                    textureId: id,
                                                    filterQuality:
                                                        videoViewParameters
                                                            .filterQuality,
                                                  ),
                                                ),
                                                // Keep the |Texture| hidden before the first frame renders. In native implementation, if no default frame size is passed (through VideoController), a starting 1 pixel sized texture/surface is created to initialize the render context & check for H/W support.
                                                // This is then resized based on the video dimensions & accordingly texture ID, texture, EGLDisplay, EGLSurface etc. (depending upon platform) are also changed. Just don't show that 1 pixel texture to the UI.
                                                // NOTE: Unmounting |Texture| causes the |MarkTextureFrameAvailable| to not do anything on GNU/Linux.
                                                if (rect.width <= 1.0 &&
                                                    rect.height <= 1.0)
                                                  Positioned.fill(
                                                    child: Container(
                                                      color: videoViewParameters
                                                          .fill,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                          return _VisualTransform(
                                            rotation: videoViewParameters
                                                .visualRotation,
                                            mirror: videoViewParameters
                                                .visualMirror,
                                            child: view,
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    );
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                if (videoViewParameters.subtitleViewConfiguration.visible &&
                    !(widget.controller.player.platform?.configuration.libass ??
                        false))
                  Positioned.fill(
                    child: _maybeRepaintBoundary(
                      child: SubtitleView(
                        controller: widget.controller,
                        key: _subtitleViewKey,
                        configuration:
                            videoViewParameters.subtitleViewConfiguration,
                      ),
                    ),
                  ),
                if (videoViewParameters.controls != null)
                  Positioned.fill(
                    child: _maybeRepaintBoundary(
                      child: videoViewParameters.controls!.call(this),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

typedef VideoControlsBuilder = Widget Function(VideoState state);

class _VisualTransform extends StatelessWidget {
  final int rotation;
  final bool mirror;
  final Widget child;

  const _VisualTransform({
    required this.rotation,
    required this.mirror,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedRotation = ((rotation % 360) + 360) % 360;
    final quarterTurns = normalizedRotation ~/ 90;
    Widget result = child;

    if (mirror) {
      result = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0),
        child: result,
      );
    }

    if (quarterTurns != 0) {
      result = RotatedBox(
        quarterTurns: quarterTurns,
        child: result,
      );
    }

    return result;
  }
}

// --------------------------------------------------

/// Makes the native window enter fullscreen.
Future<void> defaultEnterNativeFullscreen() async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      await Future.wait(
        [
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
            overlays: [],
          ),
          SystemChrome.setPreferredOrientations(
            [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
          ),
        ],
      );
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await const MethodChannel('com.alexmercerind/media_kit_video')
          .invokeMethod(
        'Utils.EnterNativeFullscreen',
      );
    }
  } catch (exception, stacktrace) {
    debugPrint(exception.toString());
    debugPrint(stacktrace.toString());
  }
}

/// Makes the native window exit fullscreen.
Future<void> defaultExitNativeFullscreen() async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      await Future.wait(
        [
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          ),
          SystemChrome.setPreferredOrientations(
            [],
          ),
        ],
      );
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await const MethodChannel('com.alexmercerind/media_kit_video')
          .invokeMethod(
        'Utils.ExitNativeFullscreen',
      );
    }
  } catch (exception, stacktrace) {
    debugPrint(exception.toString());
    debugPrint(stacktrace.toString());
  }
}
// --------------------------------------------------

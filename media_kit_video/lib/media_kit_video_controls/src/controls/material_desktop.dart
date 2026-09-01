/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
// ignore_for_file: non_constant_identifier_names
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/fullscreen.dart'
    as fullscreen_methods;
import 'package:media_kit_video/media_kit_video_controls/src/controls/extensions/duration.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/widgets/video_controls_theme_data_injector.dart';

/// {@template material_desktop_video_controls}
///
/// [Video] controls which use Material design.
///
/// {@endtemplate}
Widget MaterialDesktopVideoControls(VideoState state) {
  return MaterialDesktopVideoControlsWithAdapter(
    _MediaKitMaterialDesktopVideoControlsAdapter(state),
  );
}

/// Backend-neutral state and commands consumed by the desktop control skin.
///
/// The legacy [MaterialDesktopVideoControls] entry point adapts media-kit to
/// this interface. Applications with their own playback abstraction can use
/// [MaterialDesktopVideoControlsWithAdapter] without depending on [VideoState].
abstract class MaterialDesktopVideoControlsAdapter {
  int get playlistLength;
  bool get buffering;
  bool get playing;
  Duration get position;
  Duration get duration;
  Duration get buffer;
  double get volume;
  FocusNode? get focusNode;
  EdgeInsets get subtitlePadding;

  Stream<int> get playlistLengthStream;
  Stream<bool> get bufferingStream;
  Stream<bool> get playingStream;
  Stream<bool> get completedStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<Duration> get bufferStream;
  Stream<double> get volumeStream;

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<String?> getNativeProperty(String name);

  void setSubtitlePadding(EdgeInsets padding);
  bool isFullscreen(BuildContext context);
  Future<void> toggleFullscreen(BuildContext context);
  Future<void> exitFullscreen(BuildContext context);
}

Widget MaterialDesktopVideoControlsWithAdapter(
  MaterialDesktopVideoControlsAdapter adapter,
) {
  return MaterialDesktopVideoControlsAdapterScope(
    adapter: adapter,
    child: const VideoControlsThemeDataInjector(
      child: _MaterialDesktopVideoControls(),
    ),
  );
}

class MaterialDesktopVideoControlsAdapterScope extends InheritedWidget {
  final MaterialDesktopVideoControlsAdapter adapter;

  const MaterialDesktopVideoControlsAdapterScope({
    super.key,
    required this.adapter,
    required super.child,
  });

  static MaterialDesktopVideoControlsAdapter of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<
        MaterialDesktopVideoControlsAdapterScope>();
    assert(scope != null, 'No desktop video controls adapter found.');
    return scope!.adapter;
  }

  @override
  bool updateShouldNotify(MaterialDesktopVideoControlsAdapterScope oldWidget) =>
      !identical(adapter, oldWidget.adapter);
}

MaterialDesktopVideoControlsAdapter _adapter(BuildContext context) =>
    MaterialDesktopVideoControlsAdapterScope.of(context);

class _MediaKitMaterialDesktopVideoControlsAdapter
    implements MaterialDesktopVideoControlsAdapter {
  final VideoState state;

  const _MediaKitMaterialDesktopVideoControlsAdapter(this.state);

  VideoController get _controller => state.widget.controller;

  @override
  int get playlistLength => _controller.player.state.playlist.medias.length;

  @override
  bool get buffering => _controller.player.state.buffering;

  @override
  bool get playing => _controller.player.state.playing;

  @override
  Duration get position => _controller.player.state.position;

  @override
  Duration get duration => _controller.player.state.duration;

  @override
  Duration get buffer => _controller.player.state.buffer;

  @override
  double get volume => _controller.player.state.volume;

  @override
  FocusNode? get focusNode => state.videoViewParametersNotifier.value.focusNode;

  @override
  EdgeInsets get subtitlePadding =>
      state.widget.subtitleViewConfiguration.padding;

  @override
  Stream<int> get playlistLengthStream =>
      _controller.player.stream.playlist.map((event) => event.medias.length);

  @override
  Stream<bool> get bufferingStream => _controller.player.stream.buffering;

  @override
  Stream<bool> get playingStream => _controller.player.stream.playing;

  @override
  Stream<bool> get completedStream => _controller.player.stream.completed;

  @override
  Stream<Duration> get positionStream => _controller.player.stream.position;

  @override
  Stream<Duration> get durationStream => _controller.player.stream.duration;

  @override
  Stream<Duration> get bufferStream => _controller.player.stream.buffer;

  @override
  Stream<double> get volumeStream => _controller.player.stream.volume;

  @override
  Future<void> play() => _controller.player.play();

  @override
  Future<void> pause() => _controller.player.pause();

  @override
  Future<void> playOrPause() => _controller.player.playOrPause();

  @override
  Future<void> next() => _controller.player.next();

  @override
  Future<void> previous() => _controller.player.previous();

  @override
  Future<void> seek(Duration position) => _controller.player.seek(position);

  @override
  Future<void> setVolume(double volume) => _controller.player.setVolume(volume);

  @override
  Future<String?> getNativeProperty(String name) async {
    final dynamic platform = _controller.player.platform;
    return await platform.getProperty(name) as String?;
  }

  @override
  void setSubtitlePadding(EdgeInsets padding) {
    state.setSubtitleViewPadding(padding);
  }

  @override
  bool isFullscreen(BuildContext context) =>
      fullscreen_methods.isFullscreen(context);

  @override
  Future<void> toggleFullscreen(BuildContext context) =>
      fullscreen_methods.toggleFullscreen(context);

  @override
  Future<void> exitFullscreen(BuildContext context) =>
      fullscreen_methods.exitFullscreen(context);
}

/// [MaterialDesktopVideoControlsThemeData] available in this [context].
MaterialDesktopVideoControlsThemeData _theme(BuildContext context) =>
    FullscreenInheritedWidget.maybeOf(context) == null
        ? MaterialDesktopVideoControlsTheme.maybeOf(context)?.normal ??
            kDefaultMaterialDesktopVideoControlsThemeData
        : MaterialDesktopVideoControlsTheme.maybeOf(context)?.fullscreen ??
            kDefaultMaterialDesktopVideoControlsThemeDataFullscreen;

/// Default [MaterialDesktopVideoControlsThemeData].
const kDefaultMaterialDesktopVideoControlsThemeData =
    MaterialDesktopVideoControlsThemeData();

/// Default [MaterialDesktopVideoControlsThemeData] for fullscreen.
const kDefaultMaterialDesktopVideoControlsThemeDataFullscreen =
    MaterialDesktopVideoControlsThemeData();

/// {@template material_desktop_video_controls_theme_data}
///
/// Theming related data for [MaterialDesktopVideoControls]. These values are used to theme the descendant [MaterialDesktopVideoControls].
///
/// {@endtemplate}
class MaterialDesktopVideoControlsThemeData {
  // BEHAVIOR

  /// Whether to display seek bar.
  final bool displaySeekBar;

  /// Whether a skip next button should be displayed if there are more than one videos in the playlist.
  final bool automaticallyImplySkipNextButton;

  /// Whether a skip previous button should be displayed if there are more than one videos in the playlist.
  final bool automaticallyImplySkipPreviousButton;

  /// Modify volume on mouse scroll.
  final bool modifyVolumeOnScroll;

  /// Whether to toggle fullscreen on double press.
  final bool toggleFullscreenOnDoublePress;

  /// Whether to hide mouse on controls removal.(will need to move the mouse to be hidden check issue: https://github.com/flutter/flutter/issues/76622) works on macos without moving the mouse
  final bool hideMouseOnControlsRemoval;

  /// Whether to toggle play and pause on tap.
  final bool playAndPauseOnTap;

  /// Keyboards shortcuts.
  final Map<ShortcutActivator, VoidCallback>? keyboardShortcuts;

  /// Whether the controls are initially visible.
  final bool visibleOnMount;

  // GENERIC

  /// Padding around the controls.
  ///
  /// * Default: `EdgeInsets.zero`
  /// * Fullscreen: `MediaQuery.of(context).padding`
  final EdgeInsets? padding;

  /// [Duration] after which the controls will be hidden when there is no mouse movement.
  final Duration controlsHoverDuration;

  /// [Duration] for which the controls will be animated when shown or hidden.
  final Duration controlsTransitionDuration;

  /// Whether the controls remain mounted while hidden.
  ///
  /// This avoids rebuilding the controls on every visibility change. Hidden
  /// controls are excluded from painting, pointer input, focus and ticker
  /// updates. They are disposed with the surrounding video controls.
  final bool keepControlsMounted;

  /// Restricts controls opacity animations to the painted top, center and
  /// bottom chrome instead of allocating one full-video opacity layer.
  final bool useBoundedControlsOpacityLayers;

  /// Keeps the bounded gradients at the same 20% top and 50% bottom extents
  /// used by the legacy full-surface chrome.
  ///
  /// This is useful when migrating an existing surface to bounded opacity
  /// layers without changing its established gradient appearance.
  final bool preserveLegacyGradientExtents;

  /// Builder for the buffering indicator.
  final Widget Function(BuildContext)? bufferingIndicatorBuilder;

  // BUTTON BAR

  /// Buttons to be displayed in the primary button bar.
  final List<Widget> primaryButtonBar;

  /// Buttons to be displayed in the top button bar.
  final List<Widget> topButtonBar;

  /// Margin around the top button bar.
  final EdgeInsets topButtonBarMargin;

  /// Buttons to be displayed in the bottom button bar.
  final List<Widget> bottomButtonBar;

  /// Margin around the bottom button bar.
  final EdgeInsets bottomButtonBarMargin;

  /// Height of the button bar.
  final double buttonBarHeight;

  /// Size of the button bar buttons.
  final double buttonBarButtonSize;

  /// Color of the button bar buttons.
  final Color buttonBarButtonColor;

  // SEEK BAR

  /// [Duration] for which the seek bar will be animated when the user seeks.
  final Duration seekBarTransitionDuration;

  /// [Duration] for which the seek bar thumb will be animated when the user seeks.
  final Duration seekBarThumbTransitionDuration;

  /// Minimum interval between automatic playback-position repaints.
  ///
  /// Pointer hover and seek gestures remain immediate and are not throttled.
  final Duration seekBarPositionUpdateInterval;

  /// Margin around the seek bar.
  final EdgeInsets seekBarMargin;

  /// Height of the seek bar.
  final double seekBarHeight;

  /// Height of the seek bar when hovered.
  final double seekBarHoverHeight;

  /// Height of the seek bar [Container].
  final double seekBarContainerHeight;

  /// [Color] of the seek bar.
  final Color seekBarColor;

  /// [Color] of the hovered section in the seek bar.
  final Color seekBarHoverColor;

  /// [Color] of the playback position section in the seek bar.
  final Color seekBarPositionColor;

  /// [Color] of the playback buffer section in the seek bar.
  final Color seekBarBufferColor;

  /// Size of the seek bar thumb.
  final double seekBarThumbSize;

  /// [Color] of the seek bar thumb.
  final Color seekBarThumbColor;

  /// Fractional positions to mark independently on the seek bar.
  final List<double> seekBarMarkers;

  /// [Color] of independent seek bar markers.
  final Color seekBarMarkerColor;

  /// Width of independent seek bar markers.
  final double seekBarMarkerWidth;

  // VOLUME BAR

  /// [Color] of the volume bar.
  final Color volumeBarColor;

  /// [Color] of the active region in the volume bar.
  final Color volumeBarActiveColor;

  /// Size of the volume bar thumb.
  final double volumeBarThumbSize;

  /// [Color] of the volume bar thumb.
  final Color volumeBarThumbColor;

  /// [Duration] for which the volume bar will be animated when the user hovers.
  final Duration volumeBarTransitionDuration;

  // SUBTITLE

  /// Whether to shift the subtitles upwards when the controls are visible.
  final bool shiftSubtitlesOnControlsVisibilityChange;

  /// Whether to show video chapters on the seek bar.
  final bool showVideoChapters;

  /// Video chapters to render on the seek bar. If null, the seek bar falls back
  /// to reading chapters from the underlying player.
  final List<VideoChapter>? videoChapters;

  /// Danmaku heatmap data.
  final List<double>? danmakuHeatmap;

  /// The height of the danmaku heatmap curve.
  final double danmakuHeatmapHeight;

  /// The color of the danmaku heatmap curve.
  final Color? danmakuHeatmapColor;

  /// Whether to lock the controls to stay visible (prevents auto-hide).
  final bool lockControlsVisible;

  /// {@macro material_desktop_video_controls_theme_data}
  const MaterialDesktopVideoControlsThemeData({
    this.displaySeekBar = true,
    this.automaticallyImplySkipNextButton = true,
    this.automaticallyImplySkipPreviousButton = true,
    this.toggleFullscreenOnDoublePress = true,
    this.playAndPauseOnTap = false,
    this.modifyVolumeOnScroll = true,
    this.keyboardShortcuts,
    this.visibleOnMount = false,
    this.hideMouseOnControlsRemoval = false,
    this.padding,
    this.controlsHoverDuration = const Duration(seconds: 3),
    this.controlsTransitionDuration = const Duration(milliseconds: 150),
    this.keepControlsMounted = false,
    this.useBoundedControlsOpacityLayers = false,
    this.preserveLegacyGradientExtents = false,
    this.bufferingIndicatorBuilder,
    this.primaryButtonBar = const [],
    this.topButtonBar = const [],
    this.topButtonBarMargin = const EdgeInsets.symmetric(horizontal: 16.0),
    this.bottomButtonBar = const [
      MaterialDesktopSkipPreviousButton(),
      MaterialDesktopPlayOrPauseButton(),
      MaterialDesktopSkipNextButton(),
      MaterialDesktopVolumeButton(),
      MaterialDesktopPositionIndicator(),
      Spacer(),
      MaterialDesktopFullscreenButton(),
    ],
    this.bottomButtonBarMargin = const EdgeInsets.symmetric(horizontal: 16.0),
    this.buttonBarHeight = 56.0,
    this.buttonBarButtonSize = 28.0,
    this.buttonBarButtonColor = const Color(0xFFFFFFFF),
    this.seekBarTransitionDuration = const Duration(milliseconds: 300),
    this.seekBarThumbTransitionDuration = const Duration(milliseconds: 150),
    this.seekBarPositionUpdateInterval = const Duration(milliseconds: 66),
    this.seekBarMargin = const EdgeInsets.symmetric(horizontal: 16.0),
    this.seekBarHeight = 3.2,
    this.seekBarHoverHeight = 5.6,
    this.seekBarContainerHeight = 36.0,
    this.seekBarColor = const Color(0x3DFFFFFF),
    this.seekBarHoverColor = const Color(0x3DFFFFFF),
    this.seekBarPositionColor = const Color(0xFFFF0000),
    this.seekBarBufferColor = const Color(0x3DFFFFFF),
    this.seekBarThumbSize = 12.0,
    this.seekBarThumbColor = const Color(0xFFFF0000),
    this.seekBarMarkers = const [],
    this.seekBarMarkerColor = const Color(0xFFFFFFFF),
    this.seekBarMarkerWidth = 2.0,
    this.volumeBarColor = const Color(0x3DFFFFFF),
    this.volumeBarActiveColor = const Color(0xFFFFFFFF),
    this.volumeBarThumbSize = 12.0,
    this.volumeBarThumbColor = const Color(0xFFFFFFFF),
    this.volumeBarTransitionDuration = const Duration(milliseconds: 150),
    this.shiftSubtitlesOnControlsVisibilityChange = true,
    this.showVideoChapters = true,
    this.videoChapters,
    this.danmakuHeatmap,
    this.danmakuHeatmapHeight = 40.0,
    this.danmakuHeatmapColor,
    this.lockControlsVisible = false,
  });

  /// Creates a copy of this [MaterialDesktopVideoControlsThemeData] with the given fields replaced by the non-null parameter values.
  MaterialDesktopVideoControlsThemeData copyWith({
    bool? displaySeekBar,
    bool? automaticallyImplySkipNextButton,
    bool? automaticallyImplySkipPreviousButton,
    bool? toggleFullscreenOnDoublePress,
    bool? playAndPauseOnTap,
    bool? modifyVolumeOnScroll,
    Map<ShortcutActivator, VoidCallback>? keyboardShortcuts,
    bool? visibleOnMount,
    bool? hideMouseOnControlsRemoval,
    Duration? controlsHoverDuration,
    Duration? controlsTransitionDuration,
    bool? keepControlsMounted,
    bool? useBoundedControlsOpacityLayers,
    bool? preserveLegacyGradientExtents,
    Widget Function(BuildContext)? bufferingIndicatorBuilder,
    List<Widget>? topButtonBar,
    EdgeInsets? topButtonBarMargin,
    List<Widget>? bottomButtonBar,
    EdgeInsets? bottomButtonBarMargin,
    double? buttonBarHeight,
    double? buttonBarButtonSize,
    Color? buttonBarButtonColor,
    Duration? seekBarTransitionDuration,
    Duration? seekBarThumbTransitionDuration,
    Duration? seekBarPositionUpdateInterval,
    EdgeInsets? seekBarMargin,
    double? seekBarHeight,
    double? seekBarHoverHeight,
    double? seekBarContainerHeight,
    Color? seekBarColor,
    Color? seekBarHoverColor,
    Color? seekBarPositionColor,
    Color? seekBarBufferColor,
    double? seekBarThumbSize,
    Color? seekBarThumbColor,
    List<double>? seekBarMarkers,
    Color? seekBarMarkerColor,
    double? seekBarMarkerWidth,
    Color? volumeBarColor,
    Color? volumeBarActiveColor,
    double? volumeBarThumbSize,
    Color? volumeBarThumbColor,
    Duration? volumeBarTransitionDuration,
    bool? shiftSubtitlesOnControlsVisibilityChange,
    bool? showVideoChapters,
    List<VideoChapter>? videoChapters,
    List<double>? danmakuHeatmap,
    double? danmakuHeatmapHeight,
    Color? danmakuHeatmapColor,
    bool? lockControlsVisible,
  }) {
    return MaterialDesktopVideoControlsThemeData(
      displaySeekBar: displaySeekBar ?? this.displaySeekBar,
      automaticallyImplySkipNextButton: automaticallyImplySkipNextButton ??
          this.automaticallyImplySkipNextButton,
      automaticallyImplySkipPreviousButton:
          automaticallyImplySkipPreviousButton ??
              this.automaticallyImplySkipPreviousButton,
      toggleFullscreenOnDoublePress:
          toggleFullscreenOnDoublePress ?? this.toggleFullscreenOnDoublePress,
      playAndPauseOnTap: playAndPauseOnTap ?? this.playAndPauseOnTap,
      modifyVolumeOnScroll: modifyVolumeOnScroll ?? this.modifyVolumeOnScroll,
      keyboardShortcuts: keyboardShortcuts ?? this.keyboardShortcuts,
      visibleOnMount: visibleOnMount ?? this.visibleOnMount,
      hideMouseOnControlsRemoval:
          hideMouseOnControlsRemoval ?? this.hideMouseOnControlsRemoval,
      controlsHoverDuration:
          controlsHoverDuration ?? this.controlsHoverDuration,
      bufferingIndicatorBuilder:
          bufferingIndicatorBuilder ?? this.bufferingIndicatorBuilder,
      controlsTransitionDuration:
          controlsTransitionDuration ?? this.controlsTransitionDuration,
      keepControlsMounted: keepControlsMounted ?? this.keepControlsMounted,
      useBoundedControlsOpacityLayers: useBoundedControlsOpacityLayers ??
          this.useBoundedControlsOpacityLayers,
      preserveLegacyGradientExtents:
          preserveLegacyGradientExtents ?? this.preserveLegacyGradientExtents,
      topButtonBar: topButtonBar ?? this.topButtonBar,
      topButtonBarMargin: topButtonBarMargin ?? this.topButtonBarMargin,
      bottomButtonBar: bottomButtonBar ?? this.bottomButtonBar,
      bottomButtonBarMargin:
          bottomButtonBarMargin ?? this.bottomButtonBarMargin,
      buttonBarHeight: buttonBarHeight ?? this.buttonBarHeight,
      buttonBarButtonSize: buttonBarButtonSize ?? this.buttonBarButtonSize,
      buttonBarButtonColor: buttonBarButtonColor ?? this.buttonBarButtonColor,
      seekBarTransitionDuration:
          seekBarTransitionDuration ?? this.seekBarTransitionDuration,
      seekBarThumbTransitionDuration:
          seekBarThumbTransitionDuration ?? this.seekBarThumbTransitionDuration,
      seekBarPositionUpdateInterval:
          seekBarPositionUpdateInterval ?? this.seekBarPositionUpdateInterval,
      seekBarMargin: seekBarMargin ?? this.seekBarMargin,
      seekBarHeight: seekBarHeight ?? this.seekBarHeight,
      seekBarHoverHeight: seekBarHoverHeight ?? this.seekBarHoverHeight,
      seekBarContainerHeight:
          seekBarContainerHeight ?? this.seekBarContainerHeight,
      seekBarColor: seekBarColor ?? this.seekBarColor,
      seekBarHoverColor: seekBarHoverColor ?? this.seekBarHoverColor,
      seekBarPositionColor: seekBarPositionColor ?? this.seekBarPositionColor,
      seekBarBufferColor: seekBarBufferColor ?? this.seekBarBufferColor,
      seekBarThumbSize: seekBarThumbSize ?? this.seekBarThumbSize,
      seekBarThumbColor: seekBarThumbColor ?? this.seekBarThumbColor,
      seekBarMarkers: seekBarMarkers ?? this.seekBarMarkers,
      seekBarMarkerColor: seekBarMarkerColor ?? this.seekBarMarkerColor,
      seekBarMarkerWidth: seekBarMarkerWidth ?? this.seekBarMarkerWidth,
      volumeBarColor: volumeBarColor ?? this.volumeBarColor,
      volumeBarActiveColor: volumeBarActiveColor ?? this.volumeBarActiveColor,
      volumeBarThumbSize: volumeBarThumbSize ?? this.volumeBarThumbSize,
      volumeBarThumbColor: volumeBarThumbColor ?? this.volumeBarThumbColor,
      volumeBarTransitionDuration:
          volumeBarTransitionDuration ?? this.volumeBarTransitionDuration,
      shiftSubtitlesOnControlsVisibilityChange:
          shiftSubtitlesOnControlsVisibilityChange ??
              this.shiftSubtitlesOnControlsVisibilityChange,
      showVideoChapters: showVideoChapters ?? this.showVideoChapters,
      videoChapters: videoChapters ?? this.videoChapters,
      danmakuHeatmap: danmakuHeatmap ?? this.danmakuHeatmap,
      danmakuHeatmapHeight: danmakuHeatmapHeight ?? this.danmakuHeatmapHeight,
      danmakuHeatmapColor: danmakuHeatmapColor ?? this.danmakuHeatmapColor,
      lockControlsVisible: lockControlsVisible ?? this.lockControlsVisible,
    );
  }
}

/// {@template material_desktop_video_controls_theme}
///
/// Inherited widget which provides [MaterialDesktopVideoControlsThemeData] to descendant widgets.
///
/// {@endtemplate}
class MaterialDesktopVideoControlsTheme extends InheritedWidget {
  final MaterialDesktopVideoControlsThemeData normal;
  final MaterialDesktopVideoControlsThemeData fullscreen;
  const MaterialDesktopVideoControlsTheme({
    super.key,
    required this.normal,
    required this.fullscreen,
    required super.child,
  });

  static MaterialDesktopVideoControlsTheme? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
        MaterialDesktopVideoControlsTheme>();
  }

  static MaterialDesktopVideoControlsTheme of(BuildContext context) {
    final MaterialDesktopVideoControlsTheme? result = maybeOf(context);
    assert(
      result != null,
      'No [MaterialDesktopVideoControlsTheme] found in [context]',
    );
    return result!;
  }

  @override
  bool updateShouldNotify(MaterialDesktopVideoControlsTheme oldWidget) =>
      !identical(normal, oldWidget.normal) ||
      !identical(fullscreen, oldWidget.fullscreen);
}

/// {@macro material_desktop_video_controls}
class _MaterialDesktopVideoControls extends StatefulWidget {
  const _MaterialDesktopVideoControls();

  @override
  State<_MaterialDesktopVideoControls> createState() =>
      _MaterialDesktopVideoControlsState();
}

/// {@macro material_desktop_video_controls}
class _MaterialDesktopVideoControlsState
    extends State<_MaterialDesktopVideoControls> {
  late bool mount;
  late bool visible;
  late bool controlsActive;

  Timer? _timer;
  DateTime? _lastInteractionAt;
  bool _unmountScheduled = false;

  late bool buffering = _adapter(context).buffering;

  DateTime last = DateTime.now();

  final List<StreamSubscription> subscriptions = [];

  double get subtitleVerticalShiftOffset =>
      (_theme(context).padding?.bottom ?? 0.0) +
      (_theme(context).bottomButtonBarMargin.vertical) +
      (_theme(context).bottomButtonBar.isNotEmpty
          ? _theme(context).buttonBarHeight
          : 0.0);

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = _theme(context);
    if (subscriptions.isEmpty) {
      mount =
          theme.keepControlsMounted || theme.visibleOnMount;
      visible = theme.visibleOnMount;
      controlsActive = visible;

      subscriptions.addAll(
        [
          _adapter(context).playlistLengthStream.listen((event) {
            setState(() {});
          }),
          _adapter(context).bufferingStream.listen(
            (event) {
              setState(() {
                buffering = event;
              });
            },
          ),
        ],
      );

      if (theme.visibleOnMount) {
        _lastInteractionAt = DateTime.now();
        _scheduleAutoHide();
      }
    } else {
      if (visible &&
          !theme.lockControlsVisible &&
          (_timer == null || !_timer!.isActive)) {
        _lastInteractionAt = null;
        _scheduleAutoHide();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void shiftSubtitle() {
    if (_theme(context).shiftSubtitlesOnControlsVisibilityChange) {
      _adapter(context).setSubtitlePadding(
        _adapter(context).subtitlePadding +
            EdgeInsets.fromLTRB(
              0.0,
              0.0,
              0.0,
              subtitleVerticalShiftOffset,
            ),
      );
    }
  }

  void unshiftSubtitle() {
    if (_theme(context).shiftSubtitlesOnControlsVisibilityChange) {
      _adapter(context).setSubtitlePadding(_adapter(context).subtitlePadding);
    }
  }

  // Throttle onHover when controls are already visible.  The MouseRegion
  // covers the entire video area, so onHover fires on every pixel of mouse
  // movement (180+ times/sec on a high-refresh display).  When controls are
  // already showing the only purpose is to reset the auto-hide timer, which
  // does not need per-pixel precision.
  static const _hoverThrottleInterval = Duration(milliseconds: 200);
  DateTime _lastHoverHandledAt = DateTime.fromMillisecondsSinceEpoch(0);

  void onHover() {
    if (!mounted) return;
    final now = DateTime.now();
    // Keep the auto-hide deadline accurate for every pointer event. This is
    // cheap bookkeeping and prevents continuous mouse movement from being
    // mistaken for inactivity.
    _lastInteractionAt = now;

    if (!mount || !visible) {
      // Controls not yet visible - show them immediately.
      setState(() {
        mount = true;
        visible = true;
        controlsActive = true;
      });
      shiftSubtitle();
      _lastHoverHandledAt = now;
      _scheduleAutoHide();
      return;
    }
    // Controls already visible - throttle the remaining bookkeeping.
    if (now.difference(_lastHoverHandledAt) < _hoverThrottleInterval) {
      return;
    }
    _lastHoverHandledAt = now;
    // The subtitle offset is applied once when the controls transition from
    // hidden to visible. Reapplying the same padding while the controls are
    // already visible only invalidates layout on repeated pointer movement.
    _scheduleAutoHide();
  }

  void onEnter() {
    onHover();
  }

  void _scheduleAutoHide([Duration? delay]) {
    if (!mounted) return;
    if (_timer?.isActive ?? false) return;
    _timer = Timer(
      delay ?? _theme(context).controlsHoverDuration,
      _handleAutoHideTimer,
    );
  }

  void _handleAutoHideTimer() {
    _timer = null;
    if (!mounted || _theme(context).lockControlsVisible) return;

    final lastInteractionAt = _lastInteractionAt;
    if (lastInteractionAt != null) {
      final hoverDuration = _theme(context).controlsHoverDuration;
      final elapsed = DateTime.now().difference(lastInteractionAt);
      if (elapsed < hoverDuration) {
        _scheduleAutoHide(hoverDuration - elapsed);
        return;
      }
    }

    _hideControls();
  }

  void _hideControls() {
    if (!mounted || !visible || _theme(context).lockControlsVisible) return;

    final theme = _theme(context);
    final unmountImmediately =
        theme.controlsTransitionDuration == Duration.zero;
    setState(() {
      visible = false;
      if (unmountImmediately && !theme.keepControlsMounted) {
        // With no transition there is no reason to submit another frame only
        // to unmount the controls from the transition-end callback.
        mount = false;
      }
      if (unmountImmediately) {
        controlsActive = false;
      }
    });
    unshiftSubtitle();
  }

  void _handleControlsTransitionEnd() {
    if (_theme(context).keepControlsMounted) {
      if (!visible && controlsActive) {
        setState(() {
          controlsActive = false;
        });
      }
      return;
    }
    if (visible || !mount || _unmountScheduled) return;
    _unmountScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unmountScheduled = false;
      if (!mounted || visible || !mount) return;
      setState(() {
        mount = false;
      });
    });
  }

  void onExit() {
    if (!mounted) return;
    if (_theme(context).lockControlsVisible) return;
    _timer?.cancel();
    _timer = null;
    _lastInteractionAt = null;
    _hideControls();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        focusColor: const Color(0x00000000),
        hoverColor: const Color(0x00000000),
        splashColor: const Color(0x00000000),
        highlightColor: const Color(0x00000000),
      ),
      child: CallbackShortcuts(
        bindings: _theme(context).keyboardShortcuts ??
            {
              // Default key-board shortcuts.
              // https://support.google.com/youtube/answer/7631406
              const SingleActivator(LogicalKeyboardKey.mediaPlay): () =>
                  _adapter(context).play(),
              const SingleActivator(LogicalKeyboardKey.mediaPause): () =>
                  _adapter(context).pause(),
              const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
                  _adapter(context).playOrPause(),
              const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () =>
                  _adapter(context).next(),
              const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):
                  () => _adapter(context).previous(),
              const SingleActivator(LogicalKeyboardKey.space): () =>
                  _adapter(context).playOrPause(),
              const SingleActivator(LogicalKeyboardKey.keyJ): () {
                final rate =
                    _adapter(context).position - const Duration(seconds: 10);
                _adapter(context).seek(rate);
              },
              const SingleActivator(LogicalKeyboardKey.keyI): () {
                final rate =
                    _adapter(context).position + const Duration(seconds: 10);
                _adapter(context).seek(rate);
              },
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
                final rate =
                    _adapter(context).position - const Duration(seconds: 2);
                _adapter(context).seek(rate);
              },
              const SingleActivator(LogicalKeyboardKey.arrowRight): () {
                final rate =
                    _adapter(context).position + const Duration(seconds: 2);
                _adapter(context).seek(rate);
              },
              const SingleActivator(LogicalKeyboardKey.arrowUp): () {
                final volume = _adapter(context).volume + 5.0;
                _adapter(context).setVolume(volume.clamp(0.0, 100.0));
              },
              const SingleActivator(LogicalKeyboardKey.arrowDown): () {
                final volume = _adapter(context).volume - 5.0;
                _adapter(context).setVolume(volume.clamp(0.0, 100.0));
              },
              const SingleActivator(LogicalKeyboardKey.keyF): () =>
                  _adapter(context).toggleFullscreen(context),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  _adapter(context).exitFullscreen(context),
            },

        /// Add [Directionality] to ltr to avoid wrong animation of sides.
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Focus(
            focusNode: _adapter(context).focusNode,
            autofocus: true,
            child: Material(
              elevation: 0.0,
              borderOnForeground: false,
              animationDuration: Duration.zero,
              color: const Color(0x00000000),
              shadowColor: const Color(0x00000000),
              surfaceTintColor: const Color(0x00000000),
              child: Listener(
                onPointerDown: (_) => onHover(),
                onPointerSignal: _theme(context).modifyVolumeOnScroll
                    ? (e) {
                        if (e is PointerScrollEvent) {
                          if (e.delta.dy > 0) {
                            final volume = _adapter(context).volume - 5.0;
                            _adapter(context)
                                .setVolume(volume.clamp(0.0, 100.0));
                          }
                          if (e.delta.dy < 0) {
                            final volume = _adapter(context).volume + 5.0;
                            _adapter(context)
                                .setVolume(volume.clamp(0.0, 100.0));
                          }
                        }
                      }
                    : null,
                child: GestureDetector(
                  onTapDown: !_theme(context).playAndPauseOnTap
                      ? null
                      : (TapDownDetails details) {
                          final RenderBox box =
                              context.findRenderObject() as RenderBox;
                          final Offset localPosition =
                              box.globalToLocal(details.globalPosition);
                          const double tapPadding = 10.0;
                          if (!mount ||
                              localPosition.dy <
                                  box.size.height -
                                      subtitleVerticalShiftOffset -
                                      tapPadding) {
                            // Only play and pause when the bottom seek bar is visible
                            // and when clicking outside of the bottom seek bar region
                            _adapter(context).playOrPause();
                          }
                        },
                  onTapUp: !_theme(context).toggleFullscreenOnDoublePress
                      ? null
                      : (e) {
                          final now = DateTime.now();
                          final difference = now.difference(last);
                          last = now;
                          if (difference < const Duration(milliseconds: 400)) {
                            _adapter(context).toggleFullscreen(context);
                          }
                        },
                  onPanUpdate: _theme(context).modifyVolumeOnScroll
                      ? (e) {
                          if (e.delta.dy > 0) {
                            final volume = _adapter(context).volume - 5.0;
                            _adapter(context)
                                .setVolume(volume.clamp(0.0, 100.0));
                          }
                          if (e.delta.dy < 0) {
                            final volume = _adapter(context).volume + 5.0;
                            _adapter(context)
                                .setVolume(volume.clamp(0.0, 100.0));
                          }
                        }
                      : null,
                  child: MouseRegion(
                    cursor: (_theme(context).hideMouseOnControlsRemoval &&
                            (_theme(context).keepControlsMounted
                                ? !controlsActive
                                : !mount))
                        ? SystemMouseCursors.none
                        : SystemMouseCursors.basic,
                    onHover: (_) => onHover(),
                    onEnter: (_) => onEnter(),
                    onExit: (_) => onExit(),
                    child: Stack(
                      children: [
                        if (_theme(context).useBoundedControlsOpacityLayers)
                          _BoundedMaterialDesktopControlsChrome(
                            mount: mount,
                            visible: visible,
                            controlsActive: controlsActive,
                            buffering: buffering,
                            onTransitionEnd: _handleControlsTransitionEnd,
                            onSeekStart: () {
                              if (!mounted) return;
                              _timer?.cancel();
                              _timer = null;
                            },
                            onSeekEnd: () {
                              if (!mounted) return;
                              _lastInteractionAt = DateTime.now();
                              _scheduleAutoHide();
                            },
                          ),
                        if (!_theme(context).useBoundedControlsOpacityLayers)
                          AnimatedOpacity(
                            curve: Curves.easeInOut,
                            opacity: visible ? 1.0 : 0.0,
                            duration:
                                _theme(context).controlsTransitionDuration,
                            onEnd: _handleControlsTransitionEnd,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.bottomCenter,
                              children: [
                                // Top gradient.
                                if (_theme(context).topButtonBar.isNotEmpty)
                                  Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        stops: [
                                          0.0,
                                          0.2,
                                        ],
                                        colors: [
                                          Color(0x61000000),
                                          Color(0x00000000),
                                        ],
                                      ),
                                    ),
                                  ),
                                // Bottom gradient.
                                if (_theme(context).bottomButtonBar.isNotEmpty)
                                  Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        stops: [
                                          0.5,
                                          1.0,
                                        ],
                                        colors: [
                                          Color(0x00000000),
                                          Color(0x61000000),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (mount)
                                  Padding(
                                    padding: _theme(context).padding ??
                                        (
                                            // Add padding in fullscreen!
                                            _adapter(context)
                                                    .isFullscreen(context)
                                                ? MediaQuery.of(context).padding
                                                : EdgeInsets.zero),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          height:
                                              _theme(context).buttonBarHeight,
                                          margin: _theme(context)
                                              .topButtonBarMargin,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children:
                                                _theme(context).topButtonBar,
                                          ),
                                        ),
                                        // Only display [primaryButtonBar] if [buffering] is false.
                                        Expanded(
                                          child: AnimatedOpacity(
                                            curve: Curves.easeInOut,
                                            opacity: buffering ? 0.0 : 1.0,
                                            duration: _theme(context)
                                                .controlsTransitionDuration,
                                            child: Center(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: _theme(context)
                                                    .primaryButtonBar,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (_theme(context).displaySeekBar)
                                          Builder(
                                            builder: (context) {
                                              final controlsTheme =
                                                  _theme(context);
                                              return Transform.translate(
                                                offset: controlsTheme
                                                        .bottomButtonBar
                                                        .isNotEmpty
                                                    ? const Offset(0.0, 16.0)
                                                    : Offset.zero,
                                                child: MaterialDesktopSeekBar(
                                                  onSeekStart: () {
                                                    if (!mounted) return;
                                                    _timer?.cancel();
                                                    _timer = null;
                                                  },
                                                  onSeekEnd: () {
                                                    if (!mounted) return;
                                                    _lastInteractionAt =
                                                        DateTime.now();
                                                    _scheduleAutoHide();
                                                  },
                                                ),
                                              );
                                            },
                                          ),
                                        if (_theme(context)
                                            .bottomButtonBar
                                            .isNotEmpty)
                                          Container(
                                            height:
                                                _theme(context).buttonBarHeight,
                                            margin: _theme(context)
                                                .bottomButtonBarMargin,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.max,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.start,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: _theme(context)
                                                  .bottomButtonBar,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        // Buffering Indicator.
                        IgnorePointer(
                          child: Padding(
                            padding: _theme(context).padding ??
                                (
                                    // Add padding in fullscreen!
                                    _adapter(context).isFullscreen(context)
                                        ? MediaQuery.of(context).padding
                                        : EdgeInsets.zero),
                            child: Column(
                              children: [
                                Container(
                                  height: _theme(context).buttonBarHeight,
                                  margin: _theme(context).topButtonBarMargin,
                                ),
                                Expanded(
                                  child: Center(
                                    child: Center(
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween<double>(
                                          begin: 0.0,
                                          end: buffering ? 1.0 : 0.0,
                                        ),
                                        duration: _theme(context)
                                            .controlsTransitionDuration,
                                        builder: (context, value, child) {
                                          // Only mount the buffering indicator if the opacity is greater than 0.0.
                                          // This has been done to prevent redundant resource usage in [CircularProgressIndicator].
                                          if (value > 0.0) {
                                            return Opacity(
                                              opacity: value,
                                              child: _theme(context)
                                                      .bufferingIndicatorBuilder
                                                      ?.call(context) ??
                                                  child!,
                                            );
                                          }
                                          return const SizedBox.shrink();
                                        },
                                        child: const CircularProgressIndicator(
                                          color: Color(0xFFFFFFFF),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  height: _theme(context).buttonBarHeight,
                                  margin: _theme(context).bottomButtonBarMargin,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoundedMaterialDesktopControlsChrome extends StatelessWidget {
  final bool mount;
  final bool visible;
  final bool controlsActive;
  final bool buffering;
  final VoidCallback onTransitionEnd;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;

  const _BoundedMaterialDesktopControlsChrome({
    required this.mount,
    required this.visible,
    required this.controlsActive,
    required this.buffering,
    required this.onTransitionEnd,
    required this.onSeekStart,
    required this.onSeekEnd,
  });

  Widget _buildOpacity({
    required MaterialDesktopVideoControlsThemeData theme,
    required bool visible,
    required Widget child,
    VoidCallback? onEnd,
  }) {
    if (theme.controlsTransitionDuration == Duration.zero) {
      if (theme.keepControlsMounted) {
        return Offstage(offstage: !visible, child: child);
      }
      return visible ? child : const SizedBox.shrink();
    }
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: theme.controlsTransitionDuration,
      curve: Curves.easeInOut,
      onEnd: onEnd,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme(context);
    final padding = theme.padding ??
        (_adapter(context).isFullscreen(context)
            ? MediaQuery.of(context).padding
            : EdgeInsets.zero);

    final chrome = LayoutBuilder(
      builder: (context, constraints) {
        final legacyGradientExtents = theme.preserveLegacyGradientExtents;
        final topGradientHeight = legacyGradientExtents
            ? constraints.maxHeight * 0.2
            : (constraints.maxHeight * 0.2).clamp(0.0, 180.0).toDouble();
        final bottomGradientHeight = legacyGradientExtents
            ? constraints.maxHeight * 0.5
            : (constraints.maxHeight * 0.5).clamp(0.0, 280.0).toDouble();

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // A zero-area transition owns the unmount callback. The visible
            // chrome below is split into bounded opacity layers, so none of
            // them needs to cover the full video merely to coordinate state.
            _buildOpacity(
              theme: theme,
              visible: visible,
              onEnd: onTransitionEnd,
              child: const SizedBox.shrink(),
            ),
            if (theme.topButtonBar.isNotEmpty)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: topGradientHeight,
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: _buildOpacity(
                      theme: theme,
                      visible: visible,
                      child: mount
                          ? const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x61000000),
                                    Color(0x00000000),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            if (theme.bottomButtonBar.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: bottomGradientHeight,
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: _buildOpacity(
                      theme: theme,
                      visible: visible,
                      child: mount
                          ? const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x00000000),
                                    Color(0x61000000),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RepaintBoundary(
                    child: _buildOpacity(
                      theme: theme,
                      visible: visible,
                      child: mount
                          ? Container(
                              height: theme.buttonBarHeight,
                              margin: theme.topButtonBarMargin,
                              child: Row(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: theme.topButtonBar,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: RepaintBoundary(
                        child: _buildOpacity(
                          theme: theme,
                          visible: visible && !buffering,
                          child: mount
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: theme.primaryButtonBar,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    child: _buildOpacity(
                      theme: theme,
                      visible: visible,
                      child: mount
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (theme.displaySeekBar)
                                  Transform.translate(
                                    offset: theme.bottomButtonBar.isNotEmpty
                                        ? const Offset(0.0, 16.0)
                                        : Offset.zero,
                                    child: RepaintBoundary(
                                      child: MaterialDesktopSeekBar(
                                        active: controlsActive,
                                        onSeekStart: onSeekStart,
                                        onSeekEnd: onSeekEnd,
                                      ),
                                    ),
                                  ),
                                if (theme.bottomButtonBar.isNotEmpty)
                                  Container(
                                    height: theme.buttonBarHeight,
                                    margin: theme.bottomButtonBarMargin,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.max,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: theme.bottomButtonBar,
                                    ),
                                  ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (!theme.keepControlsMounted) return chrome;
    return TickerMode(
      enabled: controlsActive,
      child: ExcludeFocus(
        excluding: !controlsActive,
        child: IgnorePointer(
          ignoring: !controlsActive,
          child: chrome,
        ),
      ),
    );
  }
}

// SEEK BAR

class VideoChapter {
  final int index;
  final String title;
  final double time;

  const VideoChapter(this.index, this.title, this.time);
}

/// Material design seek bar.
class MaterialDesktopSeekBar extends StatefulWidget {
  final bool active;
  final VoidCallback? onSeekStart;
  final VoidCallback? onSeekEnd;

  const MaterialDesktopSeekBar({
    super.key,
    this.active = true,
    this.onSeekStart,
    this.onSeekEnd,
  });

  @override
  MaterialDesktopSeekBarState createState() => MaterialDesktopSeekBarState();
}

class MaterialDesktopSeekBarState extends State<MaterialDesktopSeekBar> {
  bool hover = false;
  bool click = false;
  double slider = 0.0;

  late MaterialDesktopVideoControlsAdapter _controls;
  late bool playing;
  late Duration position;
  late Duration duration;
  late Duration buffer;
  late Duration _positionUiUpdateInterval;

  List<VideoChapter> chapters = [];
  bool chaptersExternallyManaged = false;

  final List<StreamSubscription> subscriptions = [];
  Timer? _positionUpdateTimer;
  Duration? _pendingPosition;
  DateTime _lastPositionUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  void _updateState(VoidCallback fn) {
    if (widget.active) {
      setState(fn);
    } else {
      fn();
    }
  }

  @override
  void didUpdateWidget(MaterialDesktopSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      _positionUpdateTimer?.cancel();
      _positionUpdateTimer = null;
    } else if (!oldWidget.active && widget.active) {
      playing = _controls.playing;
      position = _pendingPosition ?? _controls.position;
      duration = _controls.duration;
      buffer = _controls.buffer;
      _pendingPosition = null;
      _lastPositionUiUpdate = DateTime.now();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextControls = _adapter(context);
    final controlsChanged =
        subscriptions.isEmpty || !identical(_controls, nextControls);
    if (controlsChanged) {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      subscriptions.clear();
      _controls = nextControls;
    }

    final controlsTheme = _theme(context);
    _positionUiUpdateInterval = controlsTheme.seekBarPositionUpdateInterval;
    chaptersExternallyManaged = controlsTheme.videoChapters != null;
    if (chaptersExternallyManaged && chapters.isNotEmpty) {
      chapters = [];
    } else if (controlsChanged && chapters.isNotEmpty) {
      chapters = [];
    }

    if (controlsChanged) {
      _positionUpdateTimer?.cancel();
      _positionUpdateTimer = null;
      _pendingPosition = null;
      playing = _controls.playing;
      position = _controls.position;
      duration = _controls.duration;
      buffer = _controls.buffer;
      _lastPositionUiUpdate = DateTime.now();

      if (!chaptersExternallyManaged &&
          duration > Duration.zero &&
          chapters.isEmpty) {
        _fetchChapters();
      }
      subscriptions.addAll(
        [
          _controls.playingStream.listen((event) {
            _updateState(() {
              playing = event;
            });
          }),
          _controls.completedStream.listen((event) {
            _positionUpdateTimer?.cancel();
            _positionUpdateTimer = null;
            _pendingPosition = null;
            _updateState(() {
              position = Duration.zero;
            });
          }),
          _controls.positionStream.listen((event) {
            if (click) return;
            _pendingPosition = event;

            if (!widget.active) {
              position = event;
              _pendingPosition = null;
              return;
            }

            final now = DateTime.now();
            final elapsed = now.difference(_lastPositionUiUpdate);
            if (elapsed >= _positionUiUpdateInterval) {
              _flushPositionUpdate(now);
            } else {
              _positionUpdateTimer ??= Timer(
                _positionUiUpdateInterval - elapsed,
                _flushPositionUpdate,
              );
            }
          }),
          _controls.durationStream.listen((event) {
            _updateState(() {
              duration = event;
            });
            if (chaptersExternallyManaged) {
              if (chapters.isNotEmpty) {
                _updateState(() {
                  chapters = [];
                });
              }
            } else if (event == Duration.zero) {
              _updateState(() {
                chapters = [];
              });
            } else if (chapters.isEmpty) {
              _fetchChapters();
            }
          }),
          _controls.bufferStream.listen((event) {
            _updateState(() {
              buffer = event;
            });
          }),
        ],
      );
    }
  }

  @override
  void dispose() {
    _positionUpdateTimer?.cancel();
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<void> _fetchChapters() async {
    try {
      if (chaptersExternallyManaged) return;

      final countStr = await _controls.getNativeProperty('chapter-list/count');
      if (countStr != null && countStr.isNotEmpty) {
        final count = int.tryParse(countStr) ?? 0;
        if (count > 0) {
          final List<VideoChapter> newChapters = [];
          for (int i = 0; i < count; i++) {
            final title =
                await _controls.getNativeProperty('chapter-list/$i/title');
            final timeStr =
                await _controls.getNativeProperty('chapter-list/$i/time');
            newChapters.add(VideoChapter(
              i,
              title ?? 'Chapter ${i + 1}',
              double.tryParse(timeStr ?? '0') ?? 0.0,
            ));
          }
          if (mounted) {
            _updateState(() {
              chapters = newChapters;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch chapters: $e');
    }
  }

  void onPointerMove(PointerMoveEvent e, BoxConstraints constraints) {
    if (!mounted) return;
    final percent = e.localPosition.dx / constraints.maxWidth;
    setState(() {
      hover = true;
      slider = percent.clamp(0.0, 1.0);
    });
    _controls.seek(duration * slider);
  }

  void onPointerDown() {
    if (!mounted) return;
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = null;
    _pendingPosition = null;
    widget.onSeekStart?.call();
    setState(() {
      click = true;
    });
  }

  void onPointerUp() {
    if (!mounted) return;
    widget.onSeekEnd?.call();
    setState(() {
      // Explicitly set the position to prevent the slider from jumping.
      click = false;
      position = duration * slider;
    });
    _controls.seek(duration * slider);
  }

  void _flushPositionUpdate([DateTime? timestamp]) {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = null;
    if (!mounted || click || _pendingPosition == null) return;

    position = _pendingPosition!;
    _pendingPosition = null;
    _lastPositionUiUpdate = timestamp ?? DateTime.now();
    if (widget.active) {
      setState(() {});
    }
  }

  void onHover(PointerHoverEvent e, BoxConstraints constraints) {
    if (!mounted) return;
    final percent = e.localPosition.dx / constraints.maxWidth;
    setState(() {
      hover = true;
      slider = percent.clamp(0.0, 1.0);
    });
  }

  void onEnter(PointerEnterEvent e, BoxConstraints constraints) {
    if (!mounted) return;
    final percent = e.localPosition.dx / constraints.maxWidth;
    setState(() {
      hover = true;
      slider = percent.clamp(0.0, 1.0);
    });
  }

  void onExit(PointerExitEvent e, BoxConstraints constraints) {
    if (!mounted) return;
    setState(() {
      hover = false;
      slider = 0.0;
    });
  }

  /// Returns the current playback position in percentage.
  double get positionPercent {
    if (position == Duration.zero || duration == Duration.zero) {
      return 0.0;
    } else {
      final value = position.inMilliseconds / duration.inMilliseconds;
      return value.clamp(0.0, 1.0);
    }
  }

  /// Returns the current playback buffer position in percentage.
  double get bufferPercent {
    if (buffer == Duration.zero || duration == Duration.zero) {
      return 0.0;
    } else {
      final value = buffer.inMilliseconds / duration.inMilliseconds;
      return value.clamp(0.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedChapters = _theme(context).videoChapters ?? chapters;

    return Container(
      clipBehavior: Clip.none,
      margin: _theme(context).seekBarMargin,
      child: LayoutBuilder(
        builder: (context, constraints) => MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (e) => onHover(e, constraints),
          onEnter: (e) => onEnter(e, constraints),
          onExit: (e) => onExit(e, constraints),
          child: Listener(
            onPointerMove: (e) => onPointerMove(e, constraints),
            onPointerDown: (e) => onPointerDown(),
            onPointerUp: (e) => onPointerUp(),
            child: Container(
              color: const Color(0x00000000),
              width: constraints.maxWidth,
              height: _theme(context).seekBarContainerHeight,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  if (_theme(context).danmakuHeatmap != null &&
                      _theme(context).danmakuHeatmap!.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom:
                          (_theme(context).seekBarContainerHeight ?? 36.0) / 2,
                      height: _theme(context).danmakuHeatmapHeight,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _DanmakuHeatmapPainter(
                            _theme(context).danmakuHeatmap!,
                            _theme(context).danmakuHeatmapColor ??
                                _theme(context)
                                    .seekBarThumbColor
                                    .withOpacity(0.35),
                          ),
                        ),
                      ),
                    ),
                  AnimatedContainer(
                    width: constraints.maxWidth,
                    height: hover
                        ? _theme(context).seekBarHoverHeight
                        : _theme(context).seekBarHeight,
                    alignment: Alignment.centerLeft,
                    duration: _theme(context).seekBarThumbTransitionDuration,
                    color: _theme(context).seekBarColor,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          width: constraints.maxWidth * slider,
                          color: _theme(context).seekBarHoverColor,
                        ),
                        Container(
                          width: constraints.maxWidth * bufferPercent,
                          color: _theme(context).seekBarBufferColor,
                        ),
                        Container(
                          width: click
                              ? constraints.maxWidth * slider
                              : constraints.maxWidth * positionPercent,
                          color: _theme(context).seekBarPositionColor,
                        ),
                        if (_theme(context).showVideoChapters &&
                            displayedChapters.isNotEmpty &&
                            duration.inMilliseconds > 0)
                          ...displayedChapters.map((chapter) {
                            final percent = chapter.time /
                                (duration.inMilliseconds / 1000.0);
                            if (percent <= 0.0 || percent >= 1.0) {
                              return const SizedBox.shrink();
                            }

                            // Check if this chapter is hovered
                            final bool isHovered = hover &&
                                (slider - percent).abs() *
                                        constraints.maxWidth <
                                    8.0;

                            return Positioned(
                              left: constraints.maxWidth * percent,
                              top: isHovered ? -2.0 : 0,
                              bottom: isHovered ? -2.0 : 0,
                              child: Container(
                                width: isHovered ? 4.0 : 2.0,
                                decoration: BoxDecoration(
                                  color: isHovered
                                      ? _theme(context).seekBarThumbColor
                                      : const Color(0x66000000),
                                  borderRadius: isHovered
                                      ? BorderRadius.circular(2.0)
                                      : null,
                                ),
                              ),
                            );
                          }),
                        ..._theme(context)
                            .seekBarMarkers
                            .where(
                              (marker) => marker > 0.0 && marker < 1.0,
                            )
                            .map((marker) {
                          final markerWidth =
                              _theme(context).seekBarMarkerWidth;
                          return Positioned(
                            left:
                                constraints.maxWidth * marker - markerWidth / 2,
                            top: -2.0,
                            bottom: -2.0,
                            child: IgnorePointer(
                              child: Container(
                                width: markerWidth,
                                decoration: BoxDecoration(
                                  color: _theme(context).seekBarMarkerColor,
                                  borderRadius:
                                      BorderRadius.circular(markerWidth / 2),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  Positioned(
                    left: click
                        ? (constraints.maxWidth -
                                _theme(context).seekBarThumbSize / 2) *
                            slider
                        : (constraints.maxWidth -
                                _theme(context).seekBarThumbSize / 2) *
                            positionPercent,
                    child: AnimatedContainer(
                      width: hover || click
                          ? _theme(context).seekBarThumbSize
                          : 0.0,
                      height: hover || click
                          ? _theme(context).seekBarThumbSize
                          : 0.0,
                      duration: _theme(context).seekBarThumbTransitionDuration,
                      decoration: BoxDecoration(
                        color: _theme(context).seekBarThumbColor,
                        borderRadius: BorderRadius.circular(
                          _theme(context).seekBarThumbSize / 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// BUTTON: PLAY/PAUSE

/// A material design play/pause button.
class MaterialDesktopPlayOrPauseButton extends StatefulWidget {
  /// Overriden icon size for [MaterialDesktopSkipPreviousButton].
  final double? iconSize;

  /// Overriden icon color for [MaterialDesktopSkipPreviousButton].
  final Color? iconColor;

  const MaterialDesktopPlayOrPauseButton({
    super.key,
    this.iconSize,
    this.iconColor,
  });

  @override
  MaterialDesktopPlayOrPauseButtonState createState() =>
      MaterialDesktopPlayOrPauseButtonState();
}

class MaterialDesktopPlayOrPauseButtonState
    extends State<MaterialDesktopPlayOrPauseButton>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    value: _adapter(context).playing ? 1 : 0,
    duration: const Duration(milliseconds: 200),
  );

  StreamSubscription<bool>? subscription;

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    subscription ??= _adapter(context).playingStream.listen((event) {
      if (event) {
        animation.forward();
      } else {
        animation.reverse();
      }
    });
  }

  @override
  void dispose() {
    animation.dispose();
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _adapter(context).playOrPause,
      iconSize: widget.iconSize ?? _theme(context).buttonBarButtonSize,
      color: widget.iconColor ?? _theme(context).buttonBarButtonColor,
      icon: AnimatedIcon(
        progress: animation,
        icon: AnimatedIcons.play_pause,
        size: widget.iconSize ?? _theme(context).buttonBarButtonSize,
        color: widget.iconColor ?? _theme(context).buttonBarButtonColor,
      ),
    );
  }
}

// BUTTON: SKIP NEXT

/// MaterialDesktop design skip next button.
class MaterialDesktopSkipNextButton extends StatelessWidget {
  /// Icon for [MaterialDesktopSkipNextButton].
  final Widget? icon;

  /// Overriden icon size for [MaterialDesktopSkipNextButton].
  final double? iconSize;

  /// Overriden icon color for [MaterialDesktopSkipNextButton].
  final Color? iconColor;

  const MaterialDesktopSkipNextButton({
    super.key,
    this.icon,
    this.iconSize,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!_theme(context).automaticallyImplySkipNextButton ||
        (_adapter(context).playlistLength > 1 &&
            _theme(context).automaticallyImplySkipNextButton)) {
      return IconButton(
        onPressed: _adapter(context).next,
        icon: icon ?? const Icon(Icons.skip_next),
        iconSize: iconSize ?? _theme(context).buttonBarButtonSize,
        color: iconColor ?? _theme(context).buttonBarButtonColor,
      );
    }
    return const SizedBox.shrink();
  }
}

// BUTTON: SKIP PREVIOUS

/// MaterialDesktop design skip previous button.
class MaterialDesktopSkipPreviousButton extends StatelessWidget {
  /// Icon for [MaterialDesktopSkipPreviousButton].
  final Widget? icon;

  /// Overriden icon size for [MaterialDesktopSkipPreviousButton].
  final double? iconSize;

  /// Overriden icon color for [MaterialDesktopSkipPreviousButton].
  final Color? iconColor;

  const MaterialDesktopSkipPreviousButton({
    super.key,
    this.icon,
    this.iconSize,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!_theme(context).automaticallyImplySkipPreviousButton ||
        (_adapter(context).playlistLength > 1 &&
            _theme(context).automaticallyImplySkipPreviousButton)) {
      return IconButton(
        onPressed: _adapter(context).previous,
        icon: icon ?? const Icon(Icons.skip_previous),
        iconSize: iconSize ?? _theme(context).buttonBarButtonSize,
        color: iconColor ?? _theme(context).buttonBarButtonColor,
      );
    }
    return const SizedBox.shrink();
  }
}

// BUTTON: FULL SCREEN

/// MaterialDesktop design fullscreen button.
class MaterialDesktopFullscreenButton extends StatelessWidget {
  /// Icon for [MaterialDesktopFullscreenButton].
  final Widget? icon;

  /// Overriden icon size for [MaterialDesktopFullscreenButton].
  final double? iconSize;

  /// Overriden icon color for [MaterialDesktopFullscreenButton].
  final Color? iconColor;

  const MaterialDesktopFullscreenButton({
    super.key,
    this.icon,
    this.iconSize,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _adapter(context).toggleFullscreen(context),
      icon: icon ??
          (_adapter(context).isFullscreen(context)
              ? const Icon(Icons.fullscreen_exit)
              : const Icon(Icons.fullscreen)),
      iconSize: iconSize ?? _theme(context).buttonBarButtonSize,
      color: iconColor ?? _theme(context).buttonBarButtonColor,
    );
  }
}

// BUTTON: CUSTOM

/// MaterialDesktop design custom button.
class MaterialDesktopCustomButton extends StatelessWidget {
  /// Icon for [MaterialDesktopCustomButton].
  final Widget? icon;

  /// Icon size for [MaterialDesktopCustomButton].
  final double? iconSize;

  /// Icon color for [MaterialDesktopCustomButton].
  final Color? iconColor;

  /// The callback that is called when the button is tapped or otherwise activated.
  final VoidCallback onPressed;

  const MaterialDesktopCustomButton({
    super.key,
    this.icon,
    this.iconSize,
    this.iconColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: icon ?? const Icon(Icons.settings),
      iconSize: iconSize ?? _theme(context).buttonBarButtonSize,
      color: iconColor ?? _theme(context).buttonBarButtonColor,
    );
  }
}

// BUTTON: VOLUME

/// MaterialDesktop design volume button & slider.
class MaterialDesktopVolumeButton extends StatefulWidget {
  /// Icon size for the volume button.
  final double? iconSize;

  /// Icon color for the volume button.
  final Color? iconColor;

  /// Mute icon.
  final Widget? volumeMuteIcon;

  /// Low volume icon.
  final Widget? volumeLowIcon;

  /// High volume icon.
  final Widget? volumeHighIcon;

  /// Width for the volume slider.
  final double? sliderWidth;

  const MaterialDesktopVolumeButton({
    super.key,
    this.iconSize,
    this.iconColor,
    this.volumeMuteIcon,
    this.volumeLowIcon,
    this.volumeHighIcon,
    this.sliderWidth,
  });

  @override
  MaterialDesktopVolumeButtonState createState() =>
      MaterialDesktopVolumeButtonState();
}

class MaterialDesktopVolumeButtonState
    extends State<MaterialDesktopVolumeButton>
    with SingleTickerProviderStateMixin {
  late double volume = _adapter(context).volume;

  StreamSubscription<double>? subscription;

  bool hover = false;

  bool mute = false;
  double _volume = 0.0;

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    subscription ??= _adapter(context).volumeStream.listen((event) {
      setState(() {
        volume = event;
      });
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (e) {
        setState(() {
          hover = true;
        });
      },
      onExit: (e) {
        setState(() {
          hover = false;
        });
      },
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            if (event.scrollDelta.dy < 0) {
              _adapter(context).setVolume(
                (volume + 5.0).clamp(0.0, 100.0),
              );
            }
            if (event.scrollDelta.dy > 0) {
              _adapter(context).setVolume(
                (volume - 5.0).clamp(0.0, 100.0),
              );
            }
          }
        },
        child: Row(
          children: [
            const SizedBox(width: 4.0),
            IconButton(
              onPressed: () async {
                if (mute) {
                  await _adapter(context).setVolume(_volume);
                  mute = !mute;
                }
                // https://github.com/media-kit/media-kit/pull/250#issuecomment-1605588306
                else if (volume == 0.0) {
                  _volume = 100.0;
                  await _adapter(context).setVolume(100.0);
                  mute = false;
                } else {
                  _volume = volume;
                  await _adapter(context).setVolume(0.0);
                  mute = !mute;
                }

                setState(() {});
              },
              iconSize: widget.iconSize ??
                  (_theme(context).buttonBarButtonSize * 0.8),
              color: widget.iconColor ?? _theme(context).buttonBarButtonColor,
              icon: AnimatedSwitcher(
                duration: _theme(context).volumeBarTransitionDuration,
                child: volume == 0.0
                    ? (widget.volumeMuteIcon ??
                        const Icon(
                          Icons.volume_off,
                          key: ValueKey(Icons.volume_off),
                        ))
                    : volume < 50.0
                        ? (widget.volumeLowIcon ??
                            const Icon(
                              Icons.volume_down,
                              key: ValueKey(Icons.volume_down),
                            ))
                        : (widget.volumeHighIcon ??
                            const Icon(
                              Icons.volume_up,
                              key: ValueKey(Icons.volume_up),
                            )),
              ),
            ),
            AnimatedOpacity(
              opacity: hover ? 1.0 : 0.0,
              duration: _theme(context).volumeBarTransitionDuration,
              child: AnimatedContainer(
                width:
                    hover ? (12.0 + (widget.sliderWidth ?? 52.0) + 18.0) : 12.0,
                duration: _theme(context).volumeBarTransitionDuration,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const SizedBox(width: 12.0),
                      SizedBox(
                        width: widget.sliderWidth ?? 52.0,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 1.2,
                            inactiveTrackColor: _theme(context).volumeBarColor,
                            activeTrackColor:
                                _theme(context).volumeBarActiveColor,
                            thumbColor: _theme(context).volumeBarThumbColor,
                            thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius:
                                  _theme(context).volumeBarThumbSize / 2,
                              elevation: 0.0,
                              pressedElevation: 0.0,
                            ),
                            trackShape: _CustomTrackShape(),
                            overlayColor: const Color(0x00000000),
                          ),
                          child: Slider(
                            value: volume.clamp(0.0, 100.0),
                            min: 0.0,
                            max: 100.0,
                            onChanged: (value) async {
                              await _adapter(context).setVolume(value);
                              mute = false;
                              setState(() {});
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 18.0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// POSITION INDICATOR

/// MaterialDesktop design position indicator.
class MaterialDesktopPositionIndicator extends StatefulWidget {
  /// Overriden [TextStyle] for the [MaterialDesktopPositionIndicator].
  final TextStyle? style;
  const MaterialDesktopPositionIndicator({super.key, this.style});

  @override
  MaterialDesktopPositionIndicatorState createState() =>
      MaterialDesktopPositionIndicatorState();
}

class MaterialDesktopPositionIndicatorState
    extends State<MaterialDesktopPositionIndicator> {
  static const _positionUiUpdateInterval = Duration(milliseconds: 66);

  late Duration position = _adapter(context).position;
  late Duration duration = _adapter(context).duration;

  final List<StreamSubscription> subscriptions = [];
  Timer? _positionUpdateTimer;
  Duration? _pendingPosition;
  DateTime _lastPositionUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (subscriptions.isEmpty) {
      subscriptions.addAll(
        [
          _adapter(context).positionStream.listen((event) {
            _pendingPosition = event;
            final now = DateTime.now();
            final elapsed = now.difference(_lastPositionUiUpdate);
            if (elapsed >= _positionUiUpdateInterval) {
              _flushPositionUpdate(now);
            } else {
              _positionUpdateTimer ??= Timer(
                _positionUiUpdateInterval - elapsed,
                _flushPositionUpdate,
              );
            }
          }),
          _adapter(context).durationStream.listen((event) {
            setState(() {
              duration = event;
            });
          }),
        ],
      );
    }
  }

  @override
  void dispose() {
    _positionUpdateTimer?.cancel();
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _flushPositionUpdate([DateTime? timestamp]) {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = null;
    if (!mounted || _pendingPosition == null) return;

    position = _pendingPosition!;
    _pendingPosition = null;
    _lastPositionUiUpdate = timestamp ?? DateTime.now();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${position.label(reference: duration)} / ${duration.label(reference: duration)}',
      style: widget.style ??
          TextStyle(
            height: 1.0,
            fontSize: 12.0,
            color: _theme(context).buttonBarButtonColor,
          ),
    );
  }
}

class _CustomTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final height = sliderTheme.trackHeight;
    final left = offset.dx;
    final top = offset.dy + (parentBox.size.height - height!) / 2;
    final width = parentBox.size.width;
    return Rect.fromLTWH(
      left,
      top,
      width,
      height,
    );
  }
}

class _DanmakuHeatmapPainter extends CustomPainter {
  final List<double> heatmap;
  final Color color;

  _DanmakuHeatmapPainter(this.heatmap, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (heatmap.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final double stepX = size.width / (heatmap.length - 1);

    path.moveTo(0, size.height);

    for (int i = 0; i < heatmap.length; i++) {
      final x = i * stepX;
      // heatmap[i] 范围是 0.0 ~ 1.0。在此将最大高度限制在给定的 height 内
      final y = size.height - (heatmap[i] * size.height);

      if (i == 0) {
        path.lineTo(x, y);
      } else {
        final prevX = (i - 1) * stepX;
        final prevY = size.height - (heatmap[i - 1] * size.height);
        final controlPointX = prevX + (stepX / 2);

        path.cubicTo(
          controlPointX,
          prevY,
          controlPointX,
          y,
          x,
          y,
        );
      }
    }

    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DanmakuHeatmapPainter oldDelegate) {
    if (oldDelegate.color != color) return true;
    if (oldDelegate.heatmap.length != heatmap.length) return true;
    for (int i = 0; i < heatmap.length; i++) {
      if (oldDelegate.heatmap[i] != heatmap[i]) return true;
    }
    return false;
  }
}

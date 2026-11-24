import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'android_native_video.dart' show androidNativeVideoRect;

/// The native viewport paints [fill] during HDR playback. Keep the Flutter
/// background clear then so a translucent fill is composited exactly once.
class IOSNativeVideoBackground extends StatelessWidget {
  const IOSNativeVideoBackground({
    super.key,
    required this.nativeHdrActive,
    required this.textureId,
    required this.pictureRect,
    required this.fill,
    required this.builder,
    this.visible = true,
    this.renderTexture = true,
    this.hideInlineVideo,
  });

  final ValueListenable<bool> nativeHdrActive;
  final ValueListenable<int?>? textureId;
  final ValueListenable<Rect?>? pictureRect;
  final ValueListenable<bool>? hideInlineVideo;
  final bool visible;
  final bool renderTexture;
  final Color fill;
  final Widget Function(Color) builder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([
          nativeHdrActive,
          textureId,
          pictureRect,
          hideInlineVideo,
        ]),
        builder: (context, _) {
          final rect = pictureRect?.value;
          final nativeReady = nativeHdrActive.value &&
              textureId?.value != null &&
              rect != null &&
              rect.width > 1 &&
              rect.height > 1 &&
              visible &&
              renderTexture &&
              !(hideInlineVideo?.value ?? false);
          return builder(nativeReady ? const Color(0x00000000) : fill);
        },
      );
}

/// Keep the UIKit composition boundary as large as the playback viewport.
/// Only its child video surface follows the fit, so native backdrop filters
/// can sample across picture edges into the player's letterbox background.
class IOSNativeVideo extends StatefulWidget {
  const IOSNativeVideo({
    super.key,
    required this.textureId,
    required this.fullscreen,
    required this.source,
    required this.fit,
    required this.alignment,
    required this.rotation,
    required this.mirror,
    required this.fill,
  });

  final int textureId;
  final bool fullscreen;
  final Size source;
  final BoxFit fit;
  final Alignment alignment;
  final int rotation;
  final bool mirror;
  final Color fill;

  @override
  State<IOSNativeVideo> createState() => _IOSNativeVideoState();
}

class _IOSNativeVideoState extends State<IOSNativeVideo> {
  static const _channel = MethodChannel('com.alexmercerind/media_kit_video');
  int? _viewId;
  Map<String, Object>? _layout;
  Map<String, Object>? _sent;
  bool _scheduled = false;

  void _scheduleLayout() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final viewId = _viewId;
      final layout = _layout;
      if (!mounted ||
          viewId == null ||
          layout == null ||
          mapEquals(layout, _sent)) {
        return;
      }
      _sent = layout;
      unawaited(_channel.invokeMethod<void>('IOSHdrVideoView.UpdateLayout', {
        'viewId': viewId,
        ...layout,
      }).catchError((Object error) {
        if (mounted) {
          debugPrint('iOS native video layout update failed: $error');
        }
      }));
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              viewport.isEmpty ||
              widget.source.isEmpty) {
            return const SizedBox.expand();
          }
          final quarterTurns = ((widget.rotation % 360) + 360) % 360 ~/ 90;
          final placement = androidNativeVideoRect(widget.source, viewport,
              widget.fit, widget.alignment, quarterTurns);
          _layout = {
            'x': placement.left / viewport.width,
            'y': placement.top / viewport.height,
            'width': placement.width / viewport.width,
            'height': placement.height / viewport.height,
            'rotation': quarterTurns * 90,
            'mirror': widget.mirror,
            'fill': widget.fill.toARGB32(),
          };
          _scheduleLayout();
          return UiKitView(
            viewType: 'media_kit_video/hdr',
            hitTestBehavior: PlatformViewHitTestBehavior.transparent,
            gestureRecognizers: const {},
            creationParams: {
              'textureId': widget.textureId,
              'fullscreen': widget.fullscreen,
              ..._layout!,
            },
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: (viewId) {
              if (!mounted) return;
              _viewId = viewId;
              _scheduleLayout();
            },
          );
        },
      );
}

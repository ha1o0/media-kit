import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The native container owns the whole playback viewport, including letterbox
/// bars. Only its child SurfaceView follows the video fit; Flutter therefore
/// composites every control above the same stable platform-view boundary.
class AndroidNativeVideo extends StatefulWidget {
  const AndroidNativeVideo(
      {super.key,
      required this.textureId,
      required this.fullscreen,
      required this.source,
      required this.fit,
      required this.alignment,
      required this.rotation,
      required this.mirror});

  final int textureId;
  final bool fullscreen;
  final Size source;
  final BoxFit fit;
  final Alignment alignment;
  final int rotation;
  final bool mirror;

  @override
  State<AndroidNativeVideo> createState() => _AndroidNativeVideoState();
}

class _AndroidNativeVideoState extends State<AndroidNativeVideo> {
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
      if (!mounted ||
          _viewId == null ||
          _layout == null ||
          mapEquals(_layout, _sent)) {
        return;
      }
      _sent = _layout;
      unawaited(_channel.invokeMethod<void>('HdrVideoView.UpdateLayout', {
        'viewId': _viewId,
        ..._layout!,
      }).catchError((Object error) {
        if (mounted) debugPrint('Native video layout update failed: $error');
      }));
    });
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
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
        };
        _scheduleLayout();
        return PlatformViewLink(
          viewType: 'media_kit_video/hdr',
          surfaceFactory: (context, controller) => AndroidViewSurface(
            controller: controller as AndroidViewController,
            hitTestBehavior: PlatformViewHitTestBehavior.transparent,
            gestureRecognizers: const {},
          ),
          onCreatePlatformView: (params) {
            final controller = PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: 'media_kit_video/hdr',
              layoutDirection: Directionality.of(context),
              creationParams: {
                'textureId': widget.textureId,
                'fullscreen': widget.fullscreen,
                ...?_layout
              },
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => params.onFocusChanged(true),
            );
            controller.addOnPlatformViewCreatedListener((id) {
              params.onPlatformViewCreated(id);
              if (!mounted) return;
              _viewId = id;
              _scheduleLayout();
            });
            controller.create();
            return controller;
          },
        );
      });
}

Rect androidNativeVideoRect(Size source, Size viewport, BoxFit fit,
    Alignment alignment, int quarterTurns) {
  if (source.isEmpty || viewport.isEmpty) return Rect.zero;
  final rotated =
      quarterTurns.isOdd ? Size(source.height, source.width) : source;
  final fitted = applyBoxFit(fit, rotated, viewport);
  final fullSize = Size(
    rotated.width * fitted.destination.width / fitted.source.width,
    rotated.height * fitted.destination.height / fitted.source.height,
  );
  return alignment.inscribe(fullSize, Offset.zero & viewport);
}

/// Mirror the native child video's geometry for blur-region mapping only.
/// The actual platform-view composition boundary stays viewport-sized.
class AndroidNativeVideoLayout extends StatelessWidget {
  const AndroidNativeVideoLayout({
    super.key,
    required this.source,
    required this.fit,
    required this.alignment,
    required this.rotation,
    required this.child,
  });
  final Size source;
  final BoxFit fit;
  final Alignment alignment;
  final int rotation;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        if (source.isEmpty ||
            !constraints.hasBoundedWidth ||
            !constraints.hasBoundedHeight ||
            constraints.biggest.isEmpty) {
          return const SizedBox.expand();
        }
        final quarterTurns = ((rotation % 360) + 360) % 360 ~/ 90;
        final placement = androidNativeVideoRect(
            source, constraints.biggest, fit, alignment, quarterTurns);
        final width = placement.width;
        final height = placement.height;
        return ClipRect(
            child: OverflowBox(
          alignment: alignment,
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          child: child,
        ));
      });
}

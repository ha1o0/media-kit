import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:media_kit_video/src/video/android_native_video.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';
import 'package:media_kit_video/src/video_view_parameters.dart';

/// A pre-blurred copy of the composited video together with the on-screen
/// rectangle it covers, for translucent panels drawn above the picture.
///
/// Flutter cannot sample a native Android video surface, and filtering a
/// video texture behind every panel costs a blur per frame. A panel instead
/// paints the part of [image] that lies beneath it.
@immutable
class VideoBackdrop {
  const VideoBackdrop({
    required this.controller,
    required this.viewport,
    required this.parameters,
  });

  final PlatformVideoController controller;

  /// Any mounted element whose render box spans the whole video viewport,
  /// letterbox bars included (the controls layer does).
  final BuildContext viewport;
  final ValueListenable<VideoViewParameters> parameters;

  /// Null until the platform has delivered a copy, or where it never will.
  ValueListenable<ui.Image?> get image => controller.backdrop;

  /// Copies are produced only while at least one panel holds a retain.
  void retain() => controller.retainBackdrop();
  void release() => controller.releaseBackdrop();

  /// Global logical rectangle of the picture inside the viewport, or null
  /// before the first layout.
  Rect? pictureRect() {
    if (!viewport.mounted) return null;
    final box = viewport.findRenderObject();
    final rect = controller.rect.value;
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty ||
        rect == null ||
        rect.width <= 1 ||
        rect.height <= 1) {
      return null;
    }
    final view = parameters.value;
    final source = Size(
      view.aspectRatio == null ? rect.width : rect.height * view.aspectRatio!,
      rect.height,
    );
    final quarterTurns = ((view.visualRotation % 360) + 360) % 360 ~/ 90;
    return androidNativeVideoRect(
      source,
      box.size,
      view.fit,
      view.alignment,
      quarterTurns,
    ).shift(box.localToGlobal(Offset.zero));
  }

  /// Maps a panel's global rectangle to the pixels of [image] beneath it.
  /// Returns null where the panel does not overlap the picture.
  static VideoBackdropMapping? mapping({
    required Rect panel,
    required Rect picture,
    required Size image,
  }) {
    final overlap = panel.intersect(picture);
    if (overlap.isEmpty || picture.isEmpty || image.isEmpty) return null;
    final sx = image.width / picture.width, sy = image.height / picture.height;
    return VideoBackdropMapping(
      Rect.fromLTRB(
        (overlap.left - picture.left) * sx,
        (overlap.top - picture.top) * sy,
        (overlap.right - picture.left) * sx,
        (overlap.bottom - picture.top) * sy,
      ),
      overlap.shift(-panel.topLeft),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VideoBackdrop &&
      identical(other.controller, controller) &&
      identical(other.viewport, viewport) &&
      identical(other.parameters, parameters);

  @override
  int get hashCode => Object.hash(
        identityHashCode(controller),
        identityHashCode(viewport),
        identityHashCode(parameters),
      );
}

/// [source] is in backdrop image pixels; [destination] in the panel's own
/// logical coordinates.
@immutable
class VideoBackdropMapping {
  const VideoBackdropMapping(this.source, this.destination);
  final Rect source;
  final Rect destination;
}

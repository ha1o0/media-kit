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

  /// Metadata belongs to this exact image, including when image decoding
  /// completes asynchronously. Older controllers have no gutter metadata.
  Rect contentRect(ui.Image image) {
    final frame = controller.backdropFrame;
    return frame != null && identical(frame.image, image)
        ? frame.contentRect
        : Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  }

  /// Copies are produced only while at least one panel holds a retain.
  void retain() => controller.retainBackdrop();
  void release() => controller.releaseBackdrop();

  /// The native video's composition boundary, letterbox bars included.
  Rect? viewportRect() {
    if (!viewport.mounted) return null;
    final box = viewport.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Global logical rectangle of the picture inside the viewport, or null
  /// before the first layout.
  Rect? pictureRect() {
    final bounds = viewportRect();
    final rect = controller.rect.value;
    if (bounds == null || rect == null || rect.width <= 1 || rect.height <= 1) {
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
      bounds.size,
      view.fit,
      view.alignment,
      quarterTurns,
    ).shift(bounds.topLeft);
  }

  /// Maps the copy, including its blurred gutter, to the picture's position.
  /// [viewport] clips the gutter at the actual native composition boundary,
  /// so an inline player's picture cannot colour the surrounding app page.
  static VideoBackdropMapping? mapping({
    required Rect panel,
    required Rect picture,
    required Size image,
    Rect? contentRect,
    Rect? viewport,
  }) {
    final content = contentRect ?? Offset.zero & image;
    if (picture.isEmpty ||
        image.isEmpty ||
        content.isEmpty ||
        content.left < 0 ||
        content.top < 0 ||
        content.right > image.width ||
        content.bottom > image.height) {
      return null;
    }
    final sx = picture.width / content.width,
        sy = picture.height / content.height;
    final extendedPicture = Rect.fromLTRB(
      picture.left - content.left * sx,
      picture.top - content.top * sy,
      picture.right + (image.width - content.right) * sx,
      picture.bottom + (image.height - content.bottom) * sy,
    );
    var overlap = panel.intersect(extendedPicture);
    if (viewport != null) overlap = overlap.intersect(viewport);
    if (overlap.isEmpty) return null;
    return VideoBackdropMapping(
      Rect.fromLTRB(
        (overlap.left - picture.left) / sx + content.left,
        (overlap.top - picture.top) / sy + content.top,
        (overlap.right - picture.left) / sx + content.left,
        (overlap.bottom - picture.top) / sy + content.top,
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

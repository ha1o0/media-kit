import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart';

/// Builds the encoded screenshot's RGB pixels directly from mpv's BGRA buffer.
/// Called in the native screenshot worker. An optional poster bound avoids
/// allocating and JPEG-encoding a full-resolution RGB image just to resize it.
Image nativeScreenshotImage({
  required Uint8List bytes,
  required int width,
  required int height,
  required int stride,
  int? maxDimension,
}) {
  if (width <= 0 ||
      height <= 0 ||
      stride < width * 4 ||
      bytes.length < (height - 1) * stride + width * 4) {
    throw ArgumentError('Invalid native screenshot dimensions');
  }
  if (maxDimension != null && maxDimension <= 0) {
    throw ArgumentError.value(maxDimension, 'maxDimension');
  }
  final ratio = maxDimension == null
      ? 1.0
      : math.min(1.0, maxDimension / math.max(width, height));
  final outputWidth = math.max(1, (width * ratio).round());
  final outputHeight = math.max(1, (height * ratio).round());
  final pixels =
      Image(width: outputWidth, height: outputHeight, numChannels: 3);
  if (ratio >= 1) {
    // Preserve the existing default screenshot's exact channel mapping.
    for (final pixel in pixels) {
      final offset = pixel.y * stride + pixel.x * 4;
      pixel.b = bytes[offset];
      pixel.g = bytes[offset + 1];
      pixel.r = bytes[offset + 2];
    }
    return pixels;
  }
  final xRatio = width / outputWidth;
  final yRatio = height / outputHeight;
  for (final pixel in pixels) {
    final sourceX = ((pixel.x + .5) * xRatio - .5).clamp(0.0, width - 1.0);
    final sourceY = ((pixel.y + .5) * yRatio - .5).clamp(0.0, height - 1.0);
    final left = sourceX.floor();
    final top = sourceY.floor();
    final right = math.min(left + 1, width - 1);
    final bottom = math.min(top + 1, height - 1);
    final xWeight = sourceX - left;
    final yWeight = sourceY - top;
    final topLeft = top * stride + left * 4;
    final topRight = top * stride + right * 4;
    final bottomLeft = bottom * stride + left * 4;
    final bottomRight = bottom * stride + right * 4;
    int channel(int channel) {
      final upper = bytes[topLeft + channel] * (1 - xWeight) +
          bytes[topRight + channel] * xWeight;
      final lower = bytes[bottomLeft + channel] * (1 - xWeight) +
          bytes[bottomRight + channel] * xWeight;
      return (upper * (1 - yWeight) + lower * yWeight).round();
    }

    pixel.b = channel(0);
    pixel.g = channel(1);
    pixel.r = channel(2);
  }
  return pixels;
}

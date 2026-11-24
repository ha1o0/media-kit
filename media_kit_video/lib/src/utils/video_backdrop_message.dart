import 'dart:typed_data';
import 'dart:ui' show Rect;

/// The native picture rectangle and its blurred black gutter are one message.
/// Older plugins send an unpadded image with the original 16-byte header.
class VideoBackdropMessage {
  const VideoBackdropMessage._(
    this.handle,
    this.width,
    this.height,
    this.contentRect,
    this.pixels,
  );

  final int handle, width, height;
  final Rect contentRect;
  final Uint8List pixels;

  static VideoBackdropMessage? parse(ByteData message) {
    const legacyHeader = 16, paddedHeader = 40, maxDimension = 96;
    if (message.lengthInBytes < legacyHeader) return null;
    final handle = message.getInt64(0, Endian.host);
    final width = message.getInt32(8, Endian.host);
    final height = message.getInt32(12, Endian.host);
    if (width <= 0 ||
        height <= 0 ||
        width > maxDimension ||
        height > maxDimension) {
      return null;
    }
    final bytes = width * height * 4;
    int header;
    Rect content;
    if (message.lengthInBytes == legacyHeader + bytes) {
      header = legacyHeader;
      content = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    } else if (message.lengthInBytes == paddedHeader + bytes &&
        message.getInt32(16, Endian.host) == 0x42474432 &&
        message.getInt32(20, Endian.host) == 2) {
      header = paddedHeader;
      final x = message.getInt32(24, Endian.host);
      final y = message.getInt32(28, Endian.host);
      final w = message.getInt32(32, Endian.host);
      final h = message.getInt32(36, Endian.host);
      if (x < 0 || y < 0 || w < 2 || h < 2 || x + w > width || y + h > height) {
        return null;
      }
      content =
          Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());
    } else {
      return null;
    }
    return VideoBackdropMessage._(handle, width, height, content,
        message.buffer.asUint8List(message.offsetInBytes + header, bytes));
  }
}

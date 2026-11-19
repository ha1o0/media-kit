import Accelerate
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

/// Scale the displayed SDR buffer before allocating an image or JPEG encoder.
/// The decoder and render context are never called, including during a seek.
enum VideoArtwork {
  static func encode(_ frame: CVPixelBuffer) -> Data? {
    guard CVPixelBufferGetPixelFormatType(frame) == kCVPixelFormatType_32BGRA else { return nil }
    let sourceWidth = CVPixelBufferGetWidth(frame)
    let sourceHeight = CVPixelBufferGetHeight(frame)
    guard sourceWidth > 0, sourceHeight > 0 else { return nil }
    let ratio = min(1, 512.0 / Double(max(sourceWidth, sourceHeight)))
    let width = max(1, Int(Double(sourceWidth) * ratio))
    let height = max(1, Int(Double(sourceHeight) * ratio))
    guard CVPixelBufferLockBaseAddress(frame, .readOnly) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
    guard let source = CVPixelBufferGetBaseAddress(frame),
      let output = calloc(height, width * 4) else { return nil }
    defer { free(output) }
    var input = vImage_Buffer(data: source, height: vImagePixelCount(sourceHeight),
      width: vImagePixelCount(sourceWidth), rowBytes: CVPixelBufferGetBytesPerRow(frame))
    var target = vImage_Buffer(data: output, height: vImagePixelCount(height),
      width: vImagePixelCount(width), rowBytes: width * 4)
    guard vImageScale_ARGB8888(&input, &target, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: output, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
      let image = context.makeImage() else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image,
      [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }
}

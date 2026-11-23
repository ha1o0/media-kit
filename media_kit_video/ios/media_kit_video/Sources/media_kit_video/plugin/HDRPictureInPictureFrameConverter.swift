import CoreImage
import CoreVideo
import Foundation

/// AVKit's preview receives a bounded SDR copy of the already composited HDR
/// frame. Keep the inline surface, subtitles, decoder and HDR target intact.
final class HDRPictureInPictureFrameConverter {
  private var context: CIContext?
  private var pool: CVPixelBufferPool?
  private var poolSize = CGSize.zero

  func reset() {
    pool = nil
    poolSize = .zero
    context?.clearCaches()
  }

  func convert(_ source: CVPixelBuffer, colorSpace: Int32) -> CVPixelBuffer? {
    guard #available(iOS 14.1, macOS 11.0, *) else { return nil }
    let format = CVPixelBufferGetPixelFormatType(source)
    guard format == kCVPixelFormatType_ARGB2101010LEPacked ||
      format == kCVPixelFormatType_64RGBAHalf else { return nil }
    let colorName: CFString
    switch colorSpace {
    case 1: colorName = CGColorSpace.itur_2100_PQ
    case 2: colorName = CGColorSpace.itur_2100_HLG
    default: return nil
    }
    guard let inputColor = CGColorSpace(name: colorName),
      let outputColor = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let sourceWidth = CVPixelBufferGetWidth(source)
    let sourceHeight = CVPixelBufferGetHeight(source)
    guard sourceWidth > 0, sourceHeight > 0 else { return nil }
    let ratio = min(1, 640.0 / Double(max(sourceWidth, sourceHeight)))
    let size = CGSize(width: max(1, floor(Double(sourceWidth) * ratio)),
      height: max(1, floor(Double(sourceHeight) * ratio)))
    if pool == nil || poolSize != size {
      pool = nil
      poolSize = size
      let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(size.width),
        kCVPixelBufferHeightKey as String: Int(size.height),
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      ]
      guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        == kCVReturnSuccess else { return nil }
    }
    var output: CVPixelBuffer?
    let limits = [kCVPixelBufferPoolAllocationThresholdKey: 3] as CFDictionary
    guard let pool = pool,
      CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, limits, &output)
        == kCVReturnSuccess, let output = output else { return nil }
    if context == nil {
      // PiP lifecycle callbacks can run after the primary Metal renderer has
      // suspended. Never submit additional GPU work for this independent copy.
      context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
    }
    let image = CIImage(cvPixelBuffer: source, options: [
      .colorSpace: inputColor, .toneMapHDRtoSDR: true,
    ]).transformed(by: CGAffineTransform(scaleX: size.width / CGFloat(sourceWidth),
      y: size.height / CGFloat(sourceHeight)))
    context?.render(image, to: output, bounds: CGRect(origin: .zero, size: size),
      colorSpace: outputColor)
    CVBufferSetAttachment(output, kCVImageBufferColorPrimariesKey,
      kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(output, kCVImageBufferTransferFunctionKey,
      kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
    return output
  }
}

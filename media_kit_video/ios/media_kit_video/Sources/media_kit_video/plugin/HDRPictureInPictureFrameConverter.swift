import CoreImage
import CoreVideo
import Foundation

/// Tags a frame AVKit will present natively. Only the Core Video attachments
/// change: the pixels, the IOSurface and the inline Metal presentation of the
/// same buffer are untouched.
enum HDRPictureInPictureTags {
  static func apply(_ pixel: CVPixelBuffer, kind: DecodedPictureInPictureColorPolicy.Kind,
                    yuv: Bool) {
    guard kind != .sdr, #available(iOS 11.0, macOS 10.13, *) else { return }
    func set(_ key: CFString, _ value: CFString) {
      if let current = CVBufferGetAttachment(pixel, key, nil)?.takeUnretainedValue(),
        CFEqual(current, value) { return }
      CVBufferSetAttachment(pixel, key, value, .shouldPropagate)
    }
    set(kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020)
    set(kCVImageBufferTransferFunctionKey, kind == .pq
      ? kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
      : kCVImageBufferTransferFunction_ITU_R_2100_HLG)
    if yuv { set(kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020) }
  }

  /// Returns a reused target to the untagged SDR contract.
  static func clear(_ pixel: CVPixelBuffer) {
    guard CVBufferGetAttachment(pixel, kCVImageBufferTransferFunctionKey, nil) != nil else { return }
    CVBufferRemoveAttachment(pixel, kCVImageBufferTransferFunctionKey)
    CVBufferRemoveAttachment(pixel, kCVImageBufferColorPrimariesKey)
  }

  /// The formats libmpv's HDR paths hand over: VideoToolbox 10-bit 4:2:0 and
  /// the packed 10-bit target that gpu-next composites subtitles into.
  static func isDecodedHdrFormat(_ format: OSType) -> Bool {
    format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
      format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
  }
}

/// Compatibility path for a system that rejects native HDR samples: AVKit
/// receives a bounded SDR copy of the already composited HDR frame. Keep the
/// inline surface, subtitles, decoder and HDR target intact.
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

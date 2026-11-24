import CoreVideo
import Foundation
import IOSurface

/// The system's per-frame Dolby metadata keys. Keep them together here: they
/// are emitted by VideoToolbox but are not declared in the public SDK.
enum DolbyVisionFrame {
  static let rpuAttachmentKey = "DolbyVisionRPUData" as CFString
  static let compatibilityAttachmentKey = "DolbyCompatibilityID" as CFString
  static let decoderOwnerAttachmentKey = "bota.DolbyVisionDecoderOwner" as CFString

  static func hasMetadata(_ pixel: CVPixelBuffer) -> Bool {
    metadata(pixel) != nil
  }

  private static func metadata(_ pixel: CVPixelBuffer) -> Data? {
    guard let data = CVBufferCopyAttachment(pixel, rpuAttachmentKey, nil) as? Data,
      !data.isEmpty else { return nil }
    return data
  }

  /// FFmpeg's av_vt_pixbuf_set_attachments removes the decoder's color tags
  /// when the AVFrame/VUI fields are unspecified (common for real P5). mpv
  /// still knows the Dolby color system, but AVSampleBufferDisplayLayer reads
  /// Core Video attachments instead. Restore its complete display description
  /// on a zero-copy wrapper, leaving mpv's decoder-owned buffer unchanged.
  static func prepare(_ pixel: CVPixelBuffer, profile: Int?, transfer: String?) -> CVPixelBuffer? {
    guard let rpu = metadata(pixel),
      let compatibility = IOSDolbyVisionOutputPolicy.compatibilityID(profile: profile, transfer: transfer),
      let surface = CVPixelBufferGetIOSurface(pixel)?.takeUnretainedValue() else { return nil }
    let formats: [OSType] = [kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
      kCVPixelFormatType_420YpCbCr10BiPlanarFullRange]
    guard formats.contains(CVPixelBufferGetPixelFormatType(pixel)) else { return nil }
    let nativeCompatibilityValue = CVBufferCopyAttachment(pixel, compatibilityAttachmentKey, nil)
    let nativeCompatibility = nativeCompatibilityValue as? String
    if nativeCompatibilityValue != nil && nativeCompatibility != compatibility { return nil }
    var output: Unmanaged<CVPixelBuffer>?
    guard CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nil, &output) == kCVReturnSuccess,
      let wrapped = output?.takeRetainedValue() else { return nil }
    if let attachments = CVBufferCopyAttachments(pixel, .shouldPropagate) {
      CVBufferSetAttachments(wrapped, attachments, .shouldPropagate)
    }
    // Retaining only the shared IOSurface does not keep a VT pool's original
    // CVPixelBuffer checked out. Keep its owner alive until AVKit releases
    // this wrapper/sample, so the decoder cannot reuse displayed pixels.
    CVBufferSetAttachment(wrapped, decoderOwnerAttachmentKey, pixel, .shouldNotPropagate)

    // A real P5 VideoToolbox/AVPlayer frame has RPU + PQ, and can omit
    // primaries, matrix and compatibility entirely. Reproduce that metadata;
    // tagging its IPT-PQc2 planes as ordinary BT.2020 YCbCr is incorrect.
    let function = compatibility == "4" ? kCVImageBufferTransferFunction_ITU_R_2100_HLG
      : kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
    if CVBufferCopyAttachment(wrapped, kCVImageBufferTransferFunctionKey, nil) == nil {
      CVBufferSetAttachment(wrapped, kCVImageBufferTransferFunctionKey, function, .shouldPropagate)
    }
    if profile == 8 {
      // P8.1 and P8.4 have an ordinary HDR10 / HLG compatible base layer.
      if CVBufferCopyAttachment(wrapped, kCVImageBufferColorPrimariesKey, nil) == nil {
        CVBufferSetAttachment(wrapped, kCVImageBufferColorPrimariesKey,
          kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
      }
      if CVBufferCopyAttachment(wrapped, kCVImageBufferYCbCrMatrixKey, nil) == nil {
        CVBufferSetAttachment(wrapped, kCVImageBufferYCbCrMatrixKey,
          kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
      }
    }
    CVBufferSetAttachment(wrapped, rpuAttachmentKey, rpu as CFData, .shouldPropagate)
    if let nativeCompatibility = nativeCompatibility {
      CVBufferSetAttachment(wrapped, compatibilityAttachmentKey, nativeCompatibility as CFString, .shouldPropagate)
      IOSurfaceSetValue(surface, compatibilityAttachmentKey, nativeCompatibility as CFString)
    } else if profile == 8 {
      CVBufferSetAttachment(wrapped, compatibilityAttachmentKey, compatibility as CFString, .shouldPropagate)
      IOSurfaceSetValue(surface, compatibilityAttachmentKey, compatibility as CFString)
    } else {
      // Missing compatibility is VideoToolbox's native P5 form, not "1".
      CVBufferRemoveAttachment(wrapped, compatibilityAttachmentKey)
      IOSurfaceRemoveValue(surface, compatibilityAttachmentKey)
    }
    // Core Animation presents the IOSurface out of process. Mirror both
    // per-frame values there, with exactly the CFData / CFString types used
    // by VideoToolbox. No pixel copy or additional decoder is needed.
    IOSurfaceSetValue(surface, rpuAttachmentKey, rpu as CFData)
    return wrapped
  }

  static func describe(_ pixel: CVPixelBuffer) -> [String: Any] {
    func value(_ key: CFString) -> String {
      CVBufferCopyAttachment(pixel, key, nil).map { String(describing: $0) } ?? "absent"
    }
    return ["pixelFormat": CVPixelBufferGetPixelFormatType(pixel),
      "rpuBytes": metadata(pixel)?.count ?? 0,
      "primaries": value(kCVImageBufferColorPrimariesKey),
      "transfer": value(kCVImageBufferTransferFunctionKey),
      "matrix": value(kCVImageBufferYCbCrMatrixKey),
      "compatibility": value(compatibilityAttachmentKey)]
  }
}

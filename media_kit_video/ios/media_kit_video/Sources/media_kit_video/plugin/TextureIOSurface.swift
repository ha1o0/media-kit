import CoreVideo
import Flutter
import Foundation
import IOSurface

#if SWIFT_PACKAGE
  import Mpv
#endif

/// libmpv gpu-next renders an IOSurface with Vulkan/MoltenVK. Flutter and AVKit
/// still receive the same BGRA CVPixelBuffer contract as the other textures.
final class TextureIOSurface: NSObject, IOSVideoFrameTexture {
  private let updateCallback: () -> Void
  private let mpvHandle: OpaquePointer
  private let hdrOutput: Bool
  var potentialHdrHeadroom: Double = 1
  private(set) var currentColorSpace: Int32 = Int32(MPV_RENDER_IOSURFACE_COLOR_SPACE_SDR.rawValue)
  private(set) var hdrMaxLuminance: Float = 1000
  private(set) var hdrMinLuminance: Float = 0.0001
  private let frameLock = NSLock()
  private var currentFrame: CVPixelBuffer?
  private var pipPool: CVPixelBufferPool?
  private var pipPoolSize = CGSize.zero
  /// Highest software composition mode the library reports: 0 none, 1 SDR
  /// subtitle blending, 2 also maps subtitles into a PQ/HLG frame.
  private var sameContextPipMode: Int32?
  private var pool: CVPixelBufferPool?
  private var poolSize: CGSize = .zero
  private var poolUsesHdr = false
  private var nextAllocation = DispatchTime(uptimeNanoseconds: 0)
  private var renderContext: OpaquePointer?
  private var reportedRenderFailure = false
  private var reportedAllocationFailure = false
  /// AVKit keeps the composited HDR targets it is still presenting. Allow for
  /// those holders, so the inline renderer is not starved of a free target.
  var retainsPictureInPictureFrames = false

  init?(handle: OpaquePointer, hdrOutput: Bool = false, updateCallback: @escaping () -> Void) {
    self.mpvHandle = handle
    self.hdrOutput = hdrOutput
    self.updateCallback = updateCallback
    super.init()

    // Keep compatibility with the vendored headers and older iOS libmpv builds.
    // On an older build, context creation fails and VideoOutput keeps its
    // current GL (device) or software (simulator) renderer.
    let status = "iosurface".withCString { api in
      "gpu-next".withCString { backend in
        var params = [
          mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                           data: UnsafeMutableRawPointer(mutating: api)),
          mpv_render_param(type: mpv_render_param_type(rawValue: 21),
                           data: UnsafeMutableRawPointer(mutating: backend)),
          mpv_render_param(),
        ]
        return mpv_render_context_create(&renderContext, handle, &params)
      }
    }
    guard status >= 0, let renderContext = renderContext else { return nil }
    mpv_render_context_set_update_callback(renderContext, { opaque in
      guard let opaque = opaque else { return }
      let callback = Unmanaged<TextureIOSurface>.fromOpaque(opaque)
        .takeUnretainedValue().updateCallback
      DispatchQueue.main.async(execute: callback)
    }, Unmanaged.passUnretained(self).toOpaque())
  }

  deinit { releaseRenderContext() }

  func releaseRenderContext() {
    guard let renderContext = renderContext else { return }
    self.renderContext = nil
    mpv_render_context_set_update_callback(renderContext, nil, nil)
    mpv_render_context_free(renderContext)
  }

  /// Peek while inline, or consume a timed frame without GPU work in PiP.
  /// The caller must first establish support with a successful inline peek;
  /// an older libmpv would otherwise ignore the private render parameter.
  func decodedPictureInPictureFrame(dequeue: Bool) -> (supported: Bool, pixel: CVPixelBuffer?) {
    guard let renderContext = renderContext else { return (false, nil) }
    var output: UnsafeMutableRawPointer?
    var skip: Int32 = 1
    let status = withUnsafeMutablePointer(to: &output) { outputPointer in
      // New producer headers name this MPV_RENDER_PARAM_IOS_PIP_FRAME.
      let frame = mpv_render_param(type: mpv_render_param_type(rawValue: 25),
        data: UnsafeMutableRawPointer(outputPointer))
      if !dequeue { return mpv_render_context_get_info(renderContext, frame) }
      return withUnsafeMutablePointer(to: &skip) { skipPointer in
        var params = [frame,
          mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: UnsafeMutableRawPointer(skipPointer)),
          mpv_render_param()]
        return mpv_render_context_render(renderContext, &params)
      }
    }
    let pixel = output.map { Unmanaged<CVPixelBuffer>.fromOpaque($0).takeRetainedValue() }
    return (status >= 0, status >= 0 ? pixel : nil)
  }

  private var sameContextPictureInPictureMode: Int32 {
    if let mode = sameContextPipMode { return mode }
    guard let renderContext = renderContext else { return 0 }
    var supported: Int32 = 0
    let status = withUnsafeMutablePointer(to: &supported) { pointer in
      mpv_render_context_get_info(renderContext, mpv_render_param(
        type: mpv_render_param_type(rawValue: 26), data: UnsafeMutableRawPointer(pointer)))
    }
    let mode = status >= 0 ? max(0, supported) : 0
    sameContextPipMode = mode
    return mode
  }

  var supportsSameContextPictureInPicture: Bool { sameContextPictureInPictureMode >= 1 }

  /// The software compositor keeps an HDR frame's PQ/HLG code values. Only a
  /// library that also maps subtitles into that transfer may be tagged as HDR;
  /// an older one would blend white text at the format's peak.
  var supportsHdrPictureInPictureComposition: Bool { sameContextPictureInPictureMode >= 2 }

  /// Compose subtitles / transformed or software frames on the same decoder.
  /// The private parameter bypasses every primary GPU operation, including
  /// pending reconfiguration. Never send it to a library that failed the probe.
  func compositedPictureInPictureFrame(
    _ size: CGSize, deliver: Bool, hdr: DecodedPictureInPictureColorPolicy.Kind? = nil
  ) -> (supported: Bool, pixel: CVPixelBuffer?) {
    guard supportsSameContextPictureInPicture, let renderContext = renderContext else { return (false, nil) }
    let hdrKind = hdr != .sdr && supportsHdrPictureInPictureComposition ? hdr : nil
    var mode: Int32 = hdrKind == nil ? 1 : 2
    var skip: Int32 = 1
    return withUnsafeMutablePointer(to: &mode) { modePointer in
      withUnsafeMutablePointer(to: &skip) { skipPointer in
        var params = [
          mpv_render_param(type: mpv_render_param_type(rawValue: 26), data: UnsafeMutableRawPointer(modePointer)),
          mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: UnsafeMutableRawPointer(skipPointer)),
        ]
        func consume() -> (supported: Bool, pixel: CVPixelBuffer?) {
          var consumeParams = params + [mpv_render_param()]
          let status = mpv_render_context_render(renderContext, &consumeParams)
          return (status >= 0, nil)
        }
        guard deliver, size.width > 0, size.height > 0 else { return consume() }
        let ratio = min(1, 640 / max(size.width, size.height))
        let targetSize = CGSize(width: max(1, (size.width * ratio).rounded(.down)),
          height: max(1, (size.height * ratio).rounded(.down)))
        if pipPoolSize != targetSize || pipPool == nil {
          pipPool = nil
          pipPoolSize = targetSize
          let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(targetSize.width),
            kCVPixelBufferHeightKey as String: Int(targetSize.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
          ]
          CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pipPool)
        }
        var frame: CVPixelBuffer?
        let limits = [kCVPixelBufferPoolAllocationThresholdKey: 3] as CFDictionary
        guard let pool = pipPool,
          CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, limits, &frame) == kCVReturnSuccess,
          let frame = frame,
          CVPixelBufferLockBaseAddress(frame, []) == kCVReturnSuccess else { return consume() }
        defer { CVPixelBufferUnlockBaseAddress(frame, []) }
        guard let pixels = CVPixelBufferGetBaseAddress(frame) else { return consume() }
        var dimensions: [Int32] = [Int32(targetSize.width), Int32(targetSize.height)]
        var stride = CVPixelBufferGetBytesPerRow(frame)
        let status = dimensions.withUnsafeMutableBytes { dimensionsPointer in
          withUnsafeMutablePointer(to: &stride) { stridePointer in
            "bgr0".withCString { formatPointer in
              params += [
                mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: dimensionsPointer.baseAddress),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: formatPointer)),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: UnsafeMutableRawPointer(stridePointer)),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: pixels), mpv_render_param(),
              ]
              return mpv_render_context_render(renderContext, &params)
            }
          }
        }
        if status >= 0 {
          // Pooled targets are reused across SDR and HDR sources.
          if let kind = hdrKind {
            HDRPictureInPictureTags.apply(frame, kind: kind, yuv: false)
          } else {
            HDRPictureInPictureTags.clear(frame)
          }
        }
        return (status >= 0 || status == MPV_ERROR_UNINITIALIZED.rawValue, status >= 0 ? frame : nil)
      }
    }
  }

  func resize(_ size: CGSize) {
    nextAllocation = DispatchTime(uptimeNanoseconds: 0)
    // On devices such as iPhone XR, allocating four source-sized 4K BGRA
    // outputs competes with the decoder's surfaces for unified memory.
    // Keep the decoded size / Flutter aspect ratio unchanged; only bound
    // the render target on devices with at most 3 GiB.
    let pixelBudget: CGFloat = 1920 * 1080
    let pixels = size.width * size.height
    let constrained = ProcessInfo.processInfo.physicalMemory <= 3 * 1024 * 1024 * 1024
    let scale = constrained && pixels > pixelBudget ? sqrt(pixelBudget / pixels) : 1
    replacePool(scale == 1 ? size : scaledSize(size, by: scale))
  }

  private func scaledSize(_ size: CGSize, by scale: CGFloat) -> CGSize {
    CGSize(width: max(1, (size.width * scale).rounded(.down)),
           height: max(1, (size.height * scale).rounded(.down)))
  }

  private func replacePool(_ size: CGSize) {
    pool = nil
    poolSize = .zero
    guard size.width >= 1, size.height >= 1,
      size.width <= CGFloat(Int32.max), size.height <= CGFloat(Int32.max) else { return }
    poolSize = size
    let attributes: [CFString: Any] = [
      kCVPixelBufferWidthKey: Int(size.width),
      kCVPixelBufferHeightKey: Int(size.height),
      kCVPixelBufferPixelFormatTypeKey: poolUsesHdr
        ? kCVPixelFormatType_ARGB2101010LEPacked
        : kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey: [:],
      kCVPixelBufferMetalCompatibilityKey: true,
    ]
    var nextPool: CVPixelBufferPool?
    if CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &nextPool) == kCVReturnSuccess {
      pool = nextPool
    }
  }

  func render(_ size: CGSize) {
    _ = renderVideoFrame(size, needsDecodedFrame: false)
  }

  private func outputColorSpace() -> Int32 {
    guard hdrOutput, potentialHdrHeadroom > 1 else { return 0 }
    func property(_ name: String) -> String? {
      guard let value = mpv_get_property_string(mpvHandle, name) else { return nil }
      defer { mpv_free(value) }
      return String(cString: value)
    }
    let transfer = property("video-out-params/gamma")?.lowercased()
    guard ["pq", "st2084", "st-2084", "hlg", "arib-std-b67"].contains(transfer ?? "") else { return 0 }
    return IOSHdrOutputPolicy.colorSpace(enabled: hdrOutput,
      potentialHeadroom: potentialHdrHeadroom,
      hint: property("target-colorspace-hint"),
      transfer: transfer,
      primaries: property("video-out-params/primaries")?.lowercased())
  }

  func renderVideoFrame(_ size: CGSize, needsDecodedFrame: Bool) -> Bool {
    guard let renderContext = renderContext,
      !needsDecodedFrame || MPVHelpers.prepareDecodedPictureInPictureFrame(renderContext) else { return false }
    var colorSpace = outputColorSpace()
    let usesHdr = colorSpace != 0
    if usesHdr {
      var peak = 0.0, minimum = 0.0
      if mpv_get_property(mpvHandle, "video-out-params/max-luma", MPV_FORMAT_DOUBLE, &peak) >= 0,
        peak > 0, peak <= 10000 { hdrMaxLuminance = Float(peak) }
      else { hdrMaxLuminance = 1000 }
      if mpv_get_property(mpvHandle, "video-out-params/min-luma", MPV_FORMAT_DOUBLE, &minimum) >= 0,
        minimum >= 0, minimum < Double(hdrMaxLuminance) { hdrMinLuminance = Float(minimum) }
      else { hdrMinLuminance = 0.0001 }
    }
    if poolUsesHdr != usesHdr {
      poolUsesHdr = usesHdr
      replacePool(poolSize)
    }
    guard let frame = allocateFrame(), let surface = CVPixelBufferGetIOSurface(frame) else {
      // Still consume the pending mpv frame; otherwise the VO waits for us.
      var skip: Int32 = 1
      withUnsafeMutablePointer(to: &skip) { pointer in
        var params = [
          mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: UnsafeMutableRawPointer(pointer)),
          mpv_render_param(),
        ]
        _ = mpv_render_context_render(renderContext, &params)
      }
      return false
    }

    let status = withUnsafeMutablePointer(to: &colorSpace) { colorSpacePointer in
      var params = [
        mpv_render_param(type: MPV_RENDER_PARAM_IOSURFACE, data: surface.toOpaque()),
        mpv_render_param(type: MPV_RENDER_PARAM_IOSURFACE_COLOR_SPACE,
                         data: UnsafeMutableRawPointer(colorSpacePointer)),
        mpv_render_param(),
      ]
      return mpv_render_context_render(renderContext, &params)
    }
    guard status >= 0 else {
      if !reportedRenderFailure {
        reportedRenderFailure = true
        NSLog("TextureIOSurface: mpv render failed (%d)", status)
      }
      return false
    }

    frameLock.lock()
    currentFrame = frame
    currentColorSpace = colorSpace
    frameLock.unlock()
    return true
  }

  private func allocateFrame() -> CVPixelBuffer? {
    guard poolSize.width > 0, DispatchTime.now() >= nextAllocation else { return nil }
    // Don't reuse a target retained by the Flutter raster thread or PiP.
    let limits = [kCVPixelBufferPoolAllocationThresholdKey:
      retainsPictureInPictureFrames ? 6 : 4] as CFDictionary
    func allocate() -> (CVReturn, CVPixelBuffer?) {
      guard let pool = pool else { return (kCVReturnAllocationFailed, nil) }
      var frame: CVPixelBuffer?
      let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, limits, &frame)
      return (status, frame)
    }
    var (status, frame) = allocate()
    // Pool contention means the consumer has not released a frame yet. Do
    // not change resolution unless there is a real allocation failure.
    if status == kCVReturnAllocationFailed {
      let longEdge = max(poolSize.width, poolSize.height)
      if longEdge > 640 {
        replacePool(scaledSize(poolSize, by: max(0.5, 640 / longEdge)))
        (status, frame) = allocate()
      }
      if status == kCVReturnAllocationFailed {
        nextAllocation = .now() + .milliseconds(250)
      }
      if !reportedAllocationFailure {
        reportedAllocationFailure = true
        NSLog("TextureIOSurface: output allocation pressure; target=%dx%d, status=%d",
          Int(poolSize.width), Int(poolSize.height), status)
      }
    }
    return status == kCVReturnSuccess ? frame : nil
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    frameLock.lock()
    defer { frameLock.unlock() }
    return currentFrame.map { Unmanaged.passRetained($0) }
  }
}

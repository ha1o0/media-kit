import CoreVideo
import Flutter
import Foundation
import IOSurface

#if SWIFT_PACKAGE
  import Mpv
#endif

/// libmpv gpu-next renders an IOSurface with Vulkan/MoltenVK. Flutter and AVKit
/// still receive the same BGRA CVPixelBuffer contract as the other textures.
final class TextureIOSurface: NSObject, ResizableTextureProtocol {
  private let updateCallback: () -> Void
  private let frameLock = NSLock()
  private var currentFrame: CVPixelBuffer?
  private var pool: CVPixelBufferPool?
  private var poolSize: CGSize = .zero
  private var nextAllocation = DispatchTime(uptimeNanoseconds: 0)
  private var renderContext: OpaquePointer?
  private var reportedRenderFailure = false
  private var reportedAllocationFailure = false

  init?(handle: OpaquePointer, updateCallback: @escaping () -> Void) {
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
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey: [:],
      kCVPixelBufferMetalCompatibilityKey: true,
    ]
    var nextPool: CVPixelBufferPool?
    if CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &nextPool) == kCVReturnSuccess {
      pool = nextPool
    }
  }

  func render(_ size: CGSize) {
    guard let renderContext = renderContext else { return }
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
      return
    }

    var params = [
      mpv_render_param(type: mpv_render_param_type(rawValue: 24), data: surface.toOpaque()),
      mpv_render_param(),
    ]
    let status = mpv_render_context_render(renderContext, &params)
    guard status >= 0 else {
      if !reportedRenderFailure {
        reportedRenderFailure = true
        NSLog("TextureIOSurface: mpv render failed (%d)", status)
      }
      return
    }

    frameLock.lock()
    currentFrame = frame
    frameLock.unlock()
  }

  private func allocateFrame() -> CVPixelBuffer? {
    guard poolSize.width > 0, DispatchTime.now() >= nextAllocation else { return nil }
    // Don't reuse a target retained by the Flutter raster thread or PiP.
    let limits = [kCVPixelBufferPoolAllocationThresholdKey: 4] as CFDictionary
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

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
  private var renderContext: OpaquePointer?
  private var reportedRenderFailure = false

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
    pool = nil
    guard size.width >= 1, size.height >= 1 else { return }
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
    // Core Video won't recycle a buffer still retained by Flutter, the PiP
    // bridge, or currentFrame. Drop an output frame if all slots are in use.
    let limits = [kCVPixelBufferPoolAllocationThresholdKey: 4] as CFDictionary
    var frame: CVPixelBuffer?
    guard let pool = pool,
      CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, limits, &frame)
        == kCVReturnSuccess,
      let frame = frame, let surface = CVPixelBufferGetIOSurface(frame) else {
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

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    frameLock.lock()
    defer { frameLock.unlock() }
    return currentFrame.map { Unmanaged.passRetained($0) }
  }
}

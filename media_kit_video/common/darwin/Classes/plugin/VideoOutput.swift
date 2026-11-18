import CoreGraphics
import Foundation
#if os(iOS)
  import Accelerate
  import UIKit

  // PiP itself only changes where frames are presented. EAGL must be released
  // when an active PiP session is leaving the foreground, but not on a
  // foreground-only PiP round trip.
  struct PictureInPictureRenderPolicy {
    var appIsActive = true
    var presenting = false

    func usesSoftware(currentlySoftware: Bool) -> Bool {
      if !appIsActive && presenting { return true }
      if appIsActive && !presenting { return false }
      return currentlySoftware
    }
  }
#endif

#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

// This class creates and manipulates the different types of FlutterTexture,
// handles resizing, rendering calls, and notify Flutter when a new frame is
// available to render.
//
// To improve the user experience, a worker is used to execute heavy tasks on a
// dedicated thread.
public class VideoOutput: NSObject {
  // Will be called on the main thread
  public typealias TextureUpdateCallback = (Int64, CGSize) -> Void

  private static let isSimulator: Bool = {
    let isSim: Bool
    #if targetEnvironment(simulator)
      isSim = true
    #else
      isSim = false
    #endif
    return isSim
  }()

  private let handle: OpaquePointer
  private let enableHardwareAcceleration: Bool
  private let renderBackend: String?
  private let registry: FlutterTextureRegistry
  private let textureUpdateCallback: TextureUpdateCallback
  private let worker: Worker = .init()
  private var width: Int64?
  private var height: Int64?
  private var texture: ResizableTextureProtocol!
  private var textureId: Int64 = -1
  private var currentSize: CGSize = CGSize.zero
  private var disposed: Bool = false
  #if os(iOS)
    private var releasePictureInPictureRenderContext: (() -> Void)?
    private var pipObserver: NSObjectProtocol?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var pipPolicy = PictureInPictureRenderPolicy()
    private var pipRendering = false
    private var pipFrameDelivery = false
    private var lastPipPreviewFrame = 0.0
  #endif

  init(
    handle: Int64,
    configuration: VideoOutputConfiguration,
    registry: FlutterTextureRegistry,
    textureUpdateCallback: @escaping TextureUpdateCallback
  ) {
    let handle = OpaquePointer(bitPattern: Int(handle))
    assert(handle != nil, "handle casting")

    self.handle = handle!
    width = configuration.width
    height = configuration.height
    enableHardwareAcceleration = configuration.enableHardwareAcceleration
    renderBackend = configuration.renderBackend
    self.registry = registry
    self.textureUpdateCallback = textureUpdateCallback

    super.init()

    #if os(iOS)
      pipObserver = NotificationCenter.default.addObserver(
        forName: Notification.Name("bota.mobile-pip-rendering"), object: nil, queue: .main
      ) { [weak self] event in
        guard let that = self,
          event.userInfo?["identity"] as? String == String(Int(bitPattern: that.handle)),
          let active = event.userInfo?["active"] as? Bool else { return }
        let frames = event.userInfo?["frames"] as? Bool ?? active
        let requestFrame = event.userInfo?["requestFrame"] as? Bool == true
        that.worker.enqueue { [weak that] in
          guard let that = that, !that.disposed else { return }
          that.pipFrameDelivery = frames
          that.pipPolicy.presenting = active
          that.updatePictureInPictureRenderer()
          if requestFrame && that.pipPolicy.appIsActive && that.pipFrameDelivery {
            that.deliverPictureInPictureFrame(force: true)
          }
        }
      }

      // Observe the transition out of active before OpenGL ES becomes
      // unavailable in the background. The PiP callback can arrive on either
      // side of it; the worker evaluates both signals in order.
      func observeLifecycle(_ name: Notification.Name, active: Bool) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
          forName: name, object: nil, queue: .main
        ) { [weak self] _ in
          self?.worker.enqueue { [weak self] in
            guard let self = self, !self.disposed else { return }
            self.pipPolicy.appIsActive = active
            self.updatePictureInPictureRenderer()
          }
        }
      }
      lifecycleObservers = [
        observeLifecycle(UIApplication.willResignActiveNotification, active: false),
        observeLifecycle(UIApplication.didBecomeActiveNotification, active: true),
      ]
    #endif

    worker.enqueue {
      self._init()
    }
  }

  deinit {
    #if os(iOS)
      if let observer = pipObserver { NotificationCenter.default.removeObserver(observer) }
      for observer in lifecycleObservers { NotificationCenter.default.removeObserver(observer) }
    #endif
    worker.cancel()

    disposed = true
    disposeTextureId()
  }

  public func setSize(width: Int64?, height: Int64?) {
    worker.enqueue {
      self.width = width
      self.height = height
    }
  }

  public func setPostProcessingEffect(_ effect: String, enabled: Bool) -> Bool {
    if disposed || texture == nil {
      return false
    }
    if effect != "anime4k.restore_cnn_s" {
      return false
    }

    worker.enqueue { [weak self] in
      guard let that = self else {
        return
      }
      _ = that.texture?.setPostProcessingEffect(effect, enabled: enabled)
    }
    return true
  }

  private func _init() {
    let enableHardwareAcceleration =
      VideoOutput.isSimulator ? false : enableHardwareAcceleration

    createTexture(hardware: enableHardwareAcceleration)
  }

  private func createTexture(hardware enableHardwareAcceleration: Bool) {

    NSLog(
      "VideoOutput: enableHardwareAcceleration: \(enableHardwareAcceleration)"
    )

    if VideoOutput.isSimulator {
      NSLog(
        "VideoOutput: warning: hardware rendering is disabled in the iOS simulator, due to an incompatibility with OpenGL ES"
      )
    }

    if enableHardwareAcceleration {
      let hardware = TextureHW(
        handle: handle,
        renderBackend: renderBackend,
        // Use `weak self` to prevent memory leaks
        updateCallback: { [weak self]() in
          guard let that = self else {
            return
          }
          that.updateCallback()
        }
      )
      #if os(iOS)
        releasePictureInPictureRenderContext = { [weak hardware] in hardware?.releaseRenderContext() }
      #endif
      texture = SafeResizableTexture(hardware)
    } else {
      let software = TextureSW(
        handle: handle,
        // Use `weak self` to prevent memory leaks
        updateCallback: { [weak self]() in
          guard let that = self else {
            return
          }
          that.updateCallback()
        }
      )
      #if os(iOS)
        releasePictureInPictureRenderContext = { [weak software] in software?.releaseRenderContext() }
      #endif
      texture = SafeResizableTexture(software)
    }

    DispatchQueue.main.sync { [weak self]() in
      guard let that = self else {
        return
      }
      that.registerTextureId()
    }
  }

  #if os(iOS)
    private func updatePictureInPictureRenderer() {
      let active = pipPolicy.usesSoftware(currentlySoftware: pipRendering)
      guard !disposed, active != pipRendering else { return }
      pipRendering = active
      if VideoOutput.isSimulator || !enableHardwareAcceleration {
        _updateCallback()
        return
      }
      // Freeing libmpv's render context deselects the active video track. Keep
      // the same media and position by restoring that track on the new context.
      let selectedVideo = mpv_get_property_string(handle, "vid")
      let videoId = selectedVideo.map { String(cString: $0) }
      if let selectedVideo = selectedVideo { mpv_free(selectedVideo) }
      var paused: Int32 = 1
      _ = mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &paused)
      let previous = textureId
      DispatchQueue.main.sync { self.registry.unregisterTexture(previous) }
      // Unregistering the Flutter texture can leave it retained on the raster
      // thread. Explicitly free its mpv context on the render worker before
      // creating a replacement: libmpv allows only one context per player.
      releasePictureInPictureRenderContext?()
      texture = nil
      currentSize = .zero
      createTexture(hardware: !active && enableHardwareAcceleration && !VideoOutput.isSimulator)
      if let videoId = videoId, videoId != "no" {
        _ = mpv_set_property_string(handle, "vid", videoId)
      }
      _ = mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &paused)
      _updateCallback()
    }
  #endif

  // Must be run on the main thread
  private func registerTextureId() {
    // Textures must be registered on the platform thread.
    textureId = registry.register(texture)
    // textureUpdateCallback must run on the main thread
    textureUpdateCallback(textureId, CGSize(width: 0, height: 0))
  }

  private func disposeTextureId() {
    let registry_ = self.registry
    let textureId_ = self.textureId
    textureId = -1
    DispatchQueue.main.async {
      // Textures must be unregistered on the platform thread
      registry_.unregisterTexture(textureId_)
    }
  }

  public func updateCallback() {
    worker.enqueue {
      self._updateCallback()
    }
  }

  private func _updateCallback() {
    var size = videoSize
    #if os(iOS)
      if pipRendering && max(size.width, size.height) > 640 {
        let ratio = 640 / max(size.width, size.height)
        size = CGSize(width: max(2, (size.width * ratio).rounded(.down)),
          height: max(2, (size.height * ratio).rounded(.down)))
      }
    #endif

    if size.width == 0 || size.height == 0 {
      return
    }

    if currentSize != size {
      currentSize = size

      texture.resize(size)
      DispatchQueue.main.sync { [weak self] in
        guard let that = self else { return }
        // textureUpdateCallback must run on the main thread
        that.textureUpdateCallback(that.textureId, size)
      }
    }

    if disposed {
      return
    }

    texture.render(size)
    #if os(iOS)
      deliverPictureInPictureFrame()
    #endif
    DispatchQueue.main.sync { [weak self] in
      guard let that = self else { return }
      // Textures must be marked as available from the main thread
      that.registry.textureFrameAvailable(that.textureId)
    }
  }

  #if os(iOS)
    private func deliverPictureInPictureFrame(force: Bool = false) {
      // Automatic PiP only takes a preview twice per second when armed. A
      // live foreground PiP needs every frame, but never resizes mpv's output.
      let previewTime = CFAbsoluteTimeGetCurrent()
      guard pipFrameDelivery, force || pipPolicy.presenting || previewTime - lastPipPreviewFrame >= 0.5,
        let pixel = texture?.copyPixelBuffer()?.takeRetainedValue(),
        CVPixelBufferGetPixelFormatType(pixel) == kCVPixelFormatType_32BGRA else { return }
      let sourceWidth = CVPixelBufferGetWidth(pixel)
      let sourceHeight = CVPixelBufferGetHeight(pixel)
      guard sourceWidth > 0, sourceHeight > 0 else { return }
      lastPipPreviewFrame = previewTime
      let ratio = min(1, 640.0 / Double(max(sourceWidth, sourceHeight)))
      let width = max(1, Int(Double(sourceWidth) * ratio))
      let height = max(1, Int(Double(sourceHeight) * ratio))
      // Hand AVKit a bounded, independent IOSurface. Only the copy is scaled;
      // Flutter and mpv keep their existing output and stream position.
      var copy: CVPixelBuffer?
      let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
        kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &copy)
      guard status == kCVReturnSuccess, let copy = copy,
        CVPixelBufferLockBaseAddress(pixel, .readOnly) == kCVReturnSuccess else { return }
      defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
      guard CVPixelBufferLockBaseAddress(copy, []) == kCVReturnSuccess else { return }
      guard let source = CVPixelBufferGetBaseAddress(pixel),
        let target = CVPixelBufferGetBaseAddress(copy) else {
        CVPixelBufferUnlockBaseAddress(copy, [])
        return
      }
      let sourceStride = CVPixelBufferGetBytesPerRow(pixel)
      let targetStride = CVPixelBufferGetBytesPerRow(copy)
      var converted = true
      if width == sourceWidth && height == sourceHeight {
        for row in 0..<height {
          memcpy(target.advanced(by: row * targetStride), source.advanced(by: row * sourceStride), width * 4)
        }
      } else {
        var input = vImage_Buffer(data: source, height: vImagePixelCount(sourceHeight),
          width: vImagePixelCount(sourceWidth), rowBytes: sourceStride)
        var output = vImage_Buffer(data: target, height: vImagePixelCount(height),
          width: vImagePixelCount(width), rowBytes: targetStride)
        converted = vImageScale_ARGB8888(&input, &output, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError
      }
      CVPixelBufferUnlockBaseAddress(copy, [])
      guard converted else { return }
      let identity = String(Int(bitPattern: handle))
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: Notification.Name("bota.mobile-video-frame"), object: nil,
          userInfo: ["identity": identity, "pixelBuffer": copy])
      }
    }
  #endif

    private var videoSize: CGSize {
        // fixed size
        if width != nil && height != nil {
            return CGSize(
                width: Double(width!),
                height: Double(height!)
            )
        }
        
        let params = MPVHelpers.getVideoOutParams(handle)
        return CGSize(
            width: Double(width ?? (params.rotate == 0 || params.rotate == 180
                                    ? params.dw
                                    : params.dh)),
            height: Double(height ?? (params.rotate == 0 || params.rotate == 180
                                      ? params.dh
                                      : params.dw))
        )
  }
}

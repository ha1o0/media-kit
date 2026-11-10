import CoreGraphics
import Foundation
#if os(iOS)
  import UIKit
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
    private var pipObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var pipRendering = false
    private var restoreHardwareOnForeground = false
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
        // OpenGL ES must not be used in the background. Only the opted-in PiP
        // session switches to mpv's software renderer, at a bounded output size.
        let foreground = UIApplication.shared.applicationState != .background
        that.worker.enqueue { [weak that] in
          guard let that = that, !that.disposed else { return }
          if !active && !foreground {
            that.restoreHardwareOnForeground = true
            return
          }
          that.switchPictureInPictureRendering(active)
        }
      }
      foregroundObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.worker.enqueue { [weak self] in
          guard let self = self, self.restoreHardwareOnForeground else { return }
          self.restoreHardwareOnForeground = false
          self.switchPictureInPictureRendering(false)
        }
      }
    #endif

    worker.enqueue {
      self._init()
    }
  }

  deinit {
    #if os(iOS)
      if let observer = pipObserver { NotificationCenter.default.removeObserver(observer) }
      if let observer = foregroundObserver { NotificationCenter.default.removeObserver(observer) }
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
      texture = SafeResizableTexture(
        TextureHW(
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
      )
    } else {
      texture = SafeResizableTexture(
        TextureSW(
          handle: handle,
          // Use `weak self` to prevent memory leaks
          updateCallback: { [weak self]() in
            guard let that = self else {
              return
            }
            that.updateCallback()
          }
        )
      )
    }

    DispatchQueue.main.sync { [weak self]() in
      guard let that = self else {
        return
      }
      that.registerTextureId()
    }
  }

  #if os(iOS)
    private func switchPictureInPictureRendering(_ active: Bool) {
      guard !disposed, active != pipRendering else { return }
      pipRendering = active
      restoreHardwareOnForeground = false
      let previous = textureId
      DispatchQueue.main.sync { self.registry.unregisterTexture(previous) }
      // Release the old render context before creating another for this player.
      texture = nil
      currentSize = .zero
      createTexture(hardware: !active && enableHardwareAcceleration && !VideoOutput.isSimulator)
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
      if pipRendering, let pixel = texture.copyPixelBuffer()?.takeRetainedValue() {
        // The texture pool reuses buffers. Copy before asynchronously enqueueing
        // to AVKit, which may retain a frame after Flutter consumes the next one.
        var copy: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, CVPixelBufferGetWidth(pixel),
          CVPixelBufferGetHeight(pixel), CVPixelBufferGetPixelFormatType(pixel),
          [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &copy)
        if status == kCVReturnSuccess, let copy = copy {
          CVPixelBufferLockBaseAddress(pixel, .readOnly)
          CVPixelBufferLockBaseAddress(copy, [])
          if let source = CVPixelBufferGetBaseAddress(pixel), let target = CVPixelBufferGetBaseAddress(copy) {
            let sourceStride = CVPixelBufferGetBytesPerRow(pixel)
            let targetStride = CVPixelBufferGetBytesPerRow(copy)
            for row in 0..<CVPixelBufferGetHeight(pixel) {
              memcpy(target.advanced(by: row * targetStride), source.advanced(by: row * sourceStride), min(sourceStride, targetStride))
            }
          }
          CVPixelBufferUnlockBaseAddress(copy, [])
          CVPixelBufferUnlockBaseAddress(pixel, .readOnly)
          DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("bota.mobile-video-frame"), object: nil,
              userInfo: ["identity": String(Int(bitPattern: self.handle)), "pixelBuffer": copy])
          }
        }
      }
    #endif
    DispatchQueue.main.sync { [weak self] in
      guard let that = self else { return }
      // Textures must be marked as available from the main thread
      that.registry.textureFrameAvailable(that.textureId)
    }
  }

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

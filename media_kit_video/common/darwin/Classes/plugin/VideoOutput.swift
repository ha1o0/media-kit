import CoreGraphics
import Foundation
#if os(iOS)
  import Accelerate
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
  public typealias TextureUpdateCallback = (Int64, CGSize, Bool) -> Void

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
  #if os(iOS)
    private var texture: IOSVideoFrameTexture!
  #else
    private var texture: ResizableTextureProtocol!
  #endif
  private var textureId: Int64 = -1
  private var currentSize: CGSize = CGSize.zero
  private var disposed: Bool = false
  #if os(iOS)
    private enum PiPFrameSource { case undecided, composited, decoded }
    private let inlineTexture = InlineVideoTexture()
    private var displayedSize = CGSize.zero
    private var lastInlineSize = CGSize.zero
    private var pipHandoff = PictureInPictureFrameHandoff()
    private var pipHandoffStartedAt: DispatchTime?
    private let pendingPipFrame = LatestPictureInPictureFrame<CVPixelBuffer>()
    private var pipFrameSource = PiPFrameSource.undecided
    private var drainsPictureInPictureFrames = false
    private var sameContextPictureInPictureFailed = false
    private let appActivity = PictureInPictureAppActivity()
    private var releasePictureInPictureRenderContext: (() -> Void)?
    private var hasUsedIosSurface = false
    private var pipObserver: NSObjectProtocol?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var pipPolicy = PictureInPictureRenderPolicy()
    private var pipRendering = false
    private var pipFrameDelivery = false
    private var lastPipPreviewFrame = 0.0
    private var hdrPipFrameConverter: HDRPictureInPictureFrameConverter?
    // Platform views can overlap while entering/leaving fullscreen. Keep all
    // live views, and replay the last frame when a paused view is attached.
    // These presentation fields are only accessed on the main thread.
    private let hdrPlatformViews = NSHashTable<HDRMetalVideoPlatformView>.weakObjects()
    private var hdrPlatformViewOrder: [ObjectIdentifier] = []
    private weak var presentingHdrView: HDRMetalVideoPlatformView?
    private var hdrFrame: (pixel: CVPixelBuffer, colorSpace: Int32, minLuminance: Float, maxLuminance: Float)?
    private var lastInlineHdrActive = false
    private var potentialHdrHeadroom: Double = 1
    // Opt-in device diagnostics; no per-frame clock reads in ordinary builds.
    private let measuresRenderTime = ProcessInfo.processInfo.environment["BOTA_IOS_RENDER_PROBE"] == "1"
    private var renderTimes: [Double] = []
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
      if #available(iOS 16.0, *) {
        potentialHdrHeadroom = Double(UIScreen.main.potentialEDRHeadroom)
      }
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
          if !frames {
            that.pendingPipFrame.discard()
            that.pipFrameSource = .undecided
            that.hdrPipFrameConverter?.reset()
          }
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
          self?.appActivity.isActive = active
          let headroom: Double
          if #available(iOS 16.0, *) {
            headroom = Double(UIScreen.main.potentialEDRHeadroom)
          } else { headroom = 1 }
          self?.worker.enqueue { [weak self] in
            guard let self = self, !self.disposed else { return }
            let currentActivity = self.appActivity.isActive
            self.pipPolicy.appIsActive = currentActivity
            self.potentialHdrHeadroom = headroom
            (self.texture as? TextureIOSurface)?.potentialHdrHeadroom = headroom
            let wasDraining = self.drainsPictureInPictureFrames
            if currentActivity { self.drainsPictureInPictureFrames = false }
            self.updatePictureInPictureRenderer()
            if currentActivity {
              if wasDraining { self._updateCallback() }
              else { self.notifyInlineFrameIfActive() }
            }
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
      #if os(iOS)
        let changed = self.width != width || self.height != height
      #endif
      self.width = width
      self.height = height
      #if os(iOS)
        // A paused video has no next frame callback. Render the retained frame
        // after an IOSurface size change; _updateCallback keeps background/PiP
        // on its existing non-GPU path and checks disposal before rendering.
        if changed, self.texture is TextureIOSurface {
          self._updateCallback()
        }
      #endif
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

  private var usesHdrSurface: Bool {
    #if os(iOS)
      return renderBackend == "iosurface-hdr"
    #else
      return false
    #endif
  }

  #if os(iOS)
    func matchesTextureId(_ id: Int64) -> Bool { textureId == id }

    var hdrState: [String: Any] {
      var headroom = 1.0
      if #available(iOS 16.0, *) { headroom = Double(UIScreen.main.potentialEDRHeadroom) }
      return ["requested": usesHdrSurface, "available": usesHdrSurface && headroom > 1,
              "active": lastInlineHdrActive, "potentialHeadroom": headroom,
              "colorSpace": hdrFrame?.colorSpace ?? 0]
    }

    func renderStats(reset: Bool, completion: @escaping ([String: Any]) -> Void) {
      let views = hdrPlatformViews.allObjects.map { view in
        ["identity": String(describing: ObjectIdentifier(view)),
         "selected": view === presentingHdrView, "fullscreen": view.fullscreen,
         "state": view.surfaceView.compositionState()] as [String: Any]
      }
      let presentation = presentingHdrView?.surfaceView.renderStats(reset: reset) ?? [:]
      worker.enqueue { [weak self] in
        guard let self = self else { return }
        var stats = IOSRenderTiming.summary(self.renderTimes)
        stats["pixelFormat"] = self.inlineTexture.latestFrame.map { CVPixelBufferGetPixelFormatType($0) } ?? 0
        stats["presentation"] = presentation
        stats["views"] = views
        if reset { self.renderTimes.removeAll(keepingCapacity: true) }
        DispatchQueue.main.async { completion(stats) }
      }
    }

    func attachHdrView(_ view: HDRMetalVideoPlatformView) {
      hdrPlatformViews.add(view)
      let identity = ObjectIdentifier(view)
      hdrPlatformViewOrder.append(identity)
      view.surfaceView.onPresentationEligibilityChanged = { [weak self] in
        self?.displayHdrFrame()
      }
      view.onDispose = { [weak self] in
        self?.hdrPlatformViewOrder.removeAll { $0 == identity }
        self?.displayHdrFrame()
      }
      displayHdrFrame()
    }

    private func displayHdrFrame() {
      let views = hdrPlatformViews.allObjects
      hdrPlatformViewOrder.removeAll { id in !views.contains { ObjectIdentifier($0) == id } }
      // An offstage inline Video can create its UIKit view after fullscreen.
      // Creation order alone must never hand it the visible player's frames.
      let ordered = hdrPlatformViewOrder.compactMap { identity in
        views.first { ObjectIdentifier($0) == identity }
      }
      let index = IOSHdrPresentationPolicy.selectedIndex(ordered.map {
        .init(eligible: $0.surfaceView.isEligibleForPresentation, fullscreen: $0.fullscreen)
      })
      let selected = index.map { ordered[$0] }
      presentingHdrView = selected
      for view in views { view.surfaceView.setPresentationEnabled(view === selected) }
      guard let view = selected else { return }
      if let frame = hdrFrame {
        view.surfaceView.display(frame.pixel, colorSpace: frame.colorSpace,
          minLuminance: frame.minLuminance, maxLuminance: frame.maxLuminance)
      }
    }
  #endif

  private func _init() {
    createTexture(hardware: enableHardwareAcceleration)
  }

  private func createTexture(hardware requestedHardwareAcceleration: Bool) {
    // A request for the new backend may still be paired with the old locked
    // libmpv. Fall back without requiring a different app or player session.
    #if os(iOS)
      let wantsIosSurface = renderBackend == "iosurface" ||
        renderBackend == "iosurface+decoded-pip" || usesHdrSurface
      if requestedHardwareAcceleration, wantsIosSurface,
        let metal = TextureIOSurface(handle: handle, hdrOutput: usesHdrSurface, updateCallback: { [weak self] in
          self?.updateCallback()
        }) {
        NSLog("VideoOutput: using gpu-next / Vulkan / MoltenVK IOSurface%@", usesHdrSurface ? " with EDR" : "")
        metal.potentialHdrHeadroom = potentialHdrHeadroom
        hasUsedIosSurface = true
        releasePictureInPictureRenderContext = { [weak metal] in metal?.releaseRenderContext() }
        texture = metal
        registerTextureOnMainThread()
        return
      }
      let legacyBackend = wantsIosSurface ? nil : renderBackend
    #else
      let legacyBackend = renderBackend
    #endif
    let enableHardwareAcceleration = requestedHardwareAcceleration && !VideoOutput.isSimulator

    NSLog("VideoOutput: enableHardwareAcceleration: \(enableHardwareAcceleration)")
    if VideoOutput.isSimulator {
      NSLog("VideoOutput: using software rendering on the iOS simulator")
    }

    if enableHardwareAcceleration {
      let hardware = TextureHW(
        handle: handle,
        renderBackend: legacyBackend,
        updateCallback: { [weak self] in self?.updateCallback() }
      )
      #if os(iOS)
        releasePictureInPictureRenderContext = { [weak hardware] in hardware?.releaseRenderContext() }
        texture = hardware
      #else
        texture = SafeResizableTexture(hardware)
      #endif
    } else {
      let software = TextureSW(
        handle: handle,
        updateCallback: { [weak self] in self?.updateCallback() }
      )
      #if os(iOS)
        releasePictureInPictureRenderContext = { [weak software] in software?.releaseRenderContext() }
        texture = software
      #else
        texture = SafeResizableTexture(software)
      #endif
    }
    registerTextureOnMainThread()
  }

  private func registerTextureOnMainThread() {
    #if os(iOS)
      guard textureId < 0 else { return }
    #endif
    DispatchQueue.main.sync { [weak self] in self?.registerTextureId() }
  }

  #if os(iOS)
    private func updatePictureInPictureRenderer() {
      guard !disposed else { return }
      // AVKit's automatic-start callback may follow willResignActive. Drain
      // the same decoder as soon as system frames are armed; never briefly
      // submit GPU work while waiting for the PiP delegate in the background.
      if (renderBackend == "iosurface+decoded-pip" || usesHdrSurface), !sameContextPictureInPictureFailed,
        let renderer = texture as? TextureIOSurface,
        pipPolicy.usesSameDecoder(framesArmed: pipFrameDelivery,
          supported: renderer.supportsSameContextPictureInPicture, currentlyDraining: drainsPictureInPictureFrames) {
        if !drainsPictureInPictureFrames {
          NSLog("VideoOutput: PiP continuing the existing decoder without inline GPU rendering")
        }
        drainsPictureInPictureFrames = true
        return
      }
      let active = pipPolicy.usesSoftware(currentlySoftware: pipRendering, framesArmed: pipFrameDelivery)
      guard active != pipRendering else { return }
      drainsPictureInPictureFrames = false
      pipRendering = active
      if !enableHardwareAcceleration || (VideoOutput.isSimulator && !hasUsedIosSurface) {
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
      pipHandoff.begin()
      pipHandoffStartedAt = .now()
      NSLog("VideoOutput: PiP renderer handoff to %@", active ? "software" : "inline")
      // Re-prime AVKit with the last valid image before the old video chain is
      // torn down. Flutter retains the same texture ID and last frame as well.
      if pipPolicy.presenting { deliverPictureInPictureFrame(force: true, handoff: true) }
      // libmpv allows only one context per player. The new context may issue
      // redraws before the reselected video track has produced a real frame.
      releasePictureInPictureRenderContext?()
      texture = nil
      currentSize = .zero
      createTexture(hardware: !active && enableHardwareAcceleration)
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
    #if os(iOS)
      textureId = registry.register(inlineTexture)
    #else
      textureId = registry.register(texture)
    #endif
    // textureUpdateCallback must run on the main thread
    textureUpdateCallback(textureId, CGSize(width: 0, height: 0), false)
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

  #if os(iOS)
    public func copyArtwork(completion: @escaping (Data?) -> Void) {
      worker.enqueue { [weak self] in
        let data: Data?
        if let self = self, !self.disposed, let frame = self.inlineTexture.latestFrame {
          data = VideoArtwork.encode(frame)
        } else {
          data = nil
        }
        DispatchQueue.main.async { completion(data) }
      }
    }
  #endif

  public func updateCallback() {
    worker.enqueue {
      self._updateCallback()
    }
  }

  private func _updateCallback() {
    guard !disposed, texture != nil else { return }
    #if os(iOS)
      if pipPolicy.appIsActive != appActivity.isActive {
        pipPolicy.appIsActive = appActivity.isActive
        updatePictureInPictureRenderer()
      }
      if drainsPictureInPictureFrames {
        drainPictureInPictureFrame()
        return
      }
      if !pipPolicy.appIsActive && !pipRendering { return }
    #endif
    let logicalSize = videoSize
    #if os(iOS)
      var size = logicalSize
      if pipRendering && max(size.width, size.height) > 640 {
        let ratio = 640 / max(size.width, size.height)
        size = CGSize(width: max(2, (size.width * ratio).rounded(.down)),
          height: max(2, (size.height * ratio).rounded(.down)))
      }
    #else
      let size = logicalSize
    #endif

    if size.width == 0 || size.height == 0 {
      return
    }

    if currentSize != size {
      currentSize = size

      texture.resize(size)
      #if !os(iOS)
        DispatchQueue.main.sync { [weak self] in
          guard let that = self else { return }
          // textureUpdateCallback must run on the main thread
          that.textureUpdateCallback(that.textureId, size, false)
        }
      #endif
    }

    if disposed {
      return
    }

    #if os(iOS)
      let renderStart = measuresRenderTime ? CFAbsoluteTimeGetCurrent() : 0
      guard texture.renderVideoFrame(size, needsDecodedFrame: pipHandoff.needsDecodedFrame),
        let frame = texture.copyPixelBuffer()?.takeRetainedValue() else { return }
      if measuresRenderTime, renderTimes.count < 3600 {
        renderTimes.append((CFAbsoluteTimeGetCurrent() - renderStart) * 1000)
      }
      let firstAfterHandoff = pipHandoff.needsDecodedFrame
      pipHandoff.didPublishFrame()
      displayedSize = logicalSize
      inlineTexture.publish(frame)
      deliverPictureInPictureFrame(handoff: firstAfterHandoff && pipPolicy.presenting)
      if let start = pipHandoffStartedAt {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        NSLog("VideoOutput: PiP first decoded replacement in %.1f ms", elapsed)
        pipHandoffStartedAt = nil
      }
      // The HDR platform view also needs Resize to leave the initial 0x0
      // layout and complete waitUntilFirstFrameRendered on the Dart side.
      notifyInlineFrameIfActive()
    #else
      texture.render(size)
      DispatchQueue.main.sync { [weak self] in
        guard let that = self else { return }
        // Textures must be marked as available from the main thread
        that.registry.textureFrameAvailable(that.textureId)
      }
    #endif
  }

  #if os(iOS)
    private func permitsDecodedPictureInPicture() -> Bool {
      guard renderBackend == "iosurface+decoded-pip" || usesHdrSurface else { return false }
      // A direct sample is before mpv's OSD and output transform.
      for property in ["sid", "secondary-sid"] {
        guard let selected = mpv_get_property_string(handle, property) else { return false }
        let disabled = String(cString: selected) == "no"
        mpv_free(selected)
        if !disabled { return false }
      }
      for property in ["brightness", "contrast", "gamma", "hue", "saturation", "video-zoom", "panscan"] {
        var value = 0.0
        guard mpv_get_property(handle, property, MPV_FORMAT_DOUBLE, &value) >= 0, value == 0 else { return false }
      }
      func videoParameter(_ property: String) -> String? {
        guard let value = mpv_get_property_string(handle, "video-out-params/\(property)") else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
      }
      guard DecodedPictureInPictureColorPolicy.accepts(
        transfer: videoParameter("gamma"), primaries: videoParameter("primaries")) else { return false }
      return MPVHelpers.getVideoOutParams(handle).rotate == 0
    }

    private func isSupportedDecodedPictureInPictureFrame(_ pixel: CVPixelBuffer) -> Bool {
      // Keep HDR on the existing composited PiP color policy.
      let format = CVPixelBufferGetPixelFormatType(pixel)
      guard format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
        format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else { return false }
      if #available(iOS 11.0, *),
        let transfer = CVBufferGetAttachment(pixel, kCVImageBufferTransferFunctionKey, nil)?.takeUnretainedValue(),
        CFEqual(transfer, kCVImageBufferTransferFunction_ITU_R_2100_HLG) ||
          CFEqual(transfer, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ) {
        return false
      }
      let width = CVPixelBufferGetWidth(pixel), height = CVPixelBufferGetHeight(pixel)
      guard height > 0, displayedSize.width > 0, displayedSize.height > 0 else { return false }
      let sourceAspect = Double(width) / Double(height)
      return abs(sourceAspect - Double(displayedSize.width / displayedSize.height)) < 0.01
    }

    private func drainPictureInPictureFrame() {
      guard let renderer = texture as? TextureIOSurface else { return }
      if pipFrameDelivery, permitsDecodedPictureInPicture(),
        let peek = renderer.decodedPictureInPictureFrame(dequeue: false).pixel,
        isSupportedDecodedPictureInPictureFrame(peek) {
        let next = renderer.decodedPictureInPictureFrame(dequeue: true)
        if next.supported {
          if let frame = next.pixel, isSupportedDecodedPictureInPictureFrame(frame) {
            pipFrameSource = .decoded
            enqueuePictureInPictureFrame(frame, handoff: false)
          } else if next.pixel != nil {
            // A format switch was consumed on this callback. Compose the
            // current frame without restarting the decoder or dropping text.
            let composed = renderer.compositedPictureInPictureFrame(videoSize, deliver: true)
            if let frame = composed.pixel {
              pipFrameSource = .composited
              enqueuePictureInPictureFrame(frame, handoff: false)
            }
          }
          return
        }
      }
      let next = renderer.compositedPictureInPictureFrame(videoSize, deliver: pipFrameDelivery)
      if let frame = next.pixel {
        pipFrameSource = .composited
        enqueuePictureInPictureFrame(frame, handoff: false)
      } else if !next.supported {
        // Rare formats that cannot be mapped keep the held PiP image while
        // using the legacy compatibility renderer. The primary GPU stays idle.
        sameContextPictureInPictureFailed = true
        drainsPictureInPictureFrames = false
        updatePictureInPictureRenderer()
      }
    }

    private func notifyInlineFrameIfActive() {
      guard pipPolicy.appIsActive, displayedSize != .zero else { return }
      let size = displayedSize
      let colorSpace = (texture as? TextureIOSurface)?.currentColorSpace ?? 0
      let minimum = (texture as? TextureIOSurface)?.hdrMinLuminance ?? 0.0001
      let peak = (texture as? TextureIOSurface)?.hdrMaxLuminance ?? 1000
      let hdrActive = usesHdrSurface && colorSpace != 0
      let frame = hdrActive ? inlineTexture.latestFrame : nil
      DispatchQueue.main.sync { [weak self] in
        guard let self = self, !self.disposed, self.textureId >= 0,
          UIApplication.shared.applicationState == .active else { return }
        if self.lastInlineSize != size || self.lastInlineHdrActive != hdrActive {
          self.lastInlineSize = size
          self.lastInlineHdrActive = hdrActive
          self.textureUpdateCallback(self.textureId, size, hdrActive)
        }
        if hdrActive {
          if let frame = frame {
            self.hdrFrame = (frame, colorSpace, minimum, peak)
            self.displayHdrFrame()
          }
        } else {
          self.hdrFrame = nil
          self.registry.textureFrameAvailable(self.textureId)
        }
      }
    }

    private func deliverPictureInPictureFrame(force: Bool = false, handoff: Bool = false) {
      // Automatic PiP only takes a preview twice per second when armed. A
      // live foreground PiP needs every frame, but never resizes mpv's output.
      let previewTime = CFAbsoluteTimeGetCurrent()
      guard pipFrameDelivery, force || pipPolicy.presenting || previewTime - lastPipPreviewFrame >= 0.5,
        let pixel = inlineTexture.latestFrame else { return }
      if permitsDecodedPictureInPicture() {
        if let renderer = texture as? TextureIOSurface,
          let decoded = renderer.decodedPictureInPictureFrame(dequeue: false).pixel,
          isSupportedDecodedPictureInPictureFrame(decoded) {
          if pipFrameSource != .decoded { NSLog("VideoOutput: PiP using decoder-owned VideoToolbox frames") }
          pipFrameSource = .decoded
          lastPipPreviewFrame = previewTime
          enqueuePictureInPictureFrame(decoded, handoff: handoff)
          return
        }
      }
      pipFrameSource = .composited
      if CVPixelBufferGetPixelFormatType(pixel) != kCVPixelFormatType_32BGRA {
        guard let renderer = texture as? TextureIOSurface else { return }
        if hdrPipFrameConverter == nil {
          hdrPipFrameConverter = HDRPictureInPictureFrameConverter()
        }
        guard let copy = hdrPipFrameConverter?.convert(pixel, colorSpace: renderer.currentColorSpace)
          else { return }
        lastPipPreviewFrame = previewTime
        enqueuePictureInPictureFrame(copy, handoff: handoff)
        return
      }
      guard CVPixelBufferGetPixelFormatType(pixel) == kCVPixelFormatType_32BGRA else { return }
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
      enqueuePictureInPictureFrame(copy, handoff: handoff)
    }

    private func enqueuePictureInPictureFrame(_ pixel: CVPixelBuffer, handoff: Bool) {
      guard pendingPipFrame.store(pixel, handoff: handoff) else { return }
      let identity = String(Int(bitPattern: handle))
      DispatchQueue.main.async { [weak self] in
        guard let frame = self?.pendingPipFrame.take() else { return }
        NotificationCenter.default.post(name: Notification.Name("bota.mobile-video-frame"), object: nil,
          userInfo: ["identity": identity, "pixelBuffer": frame.frame, "renderHandoff": frame.handoff])
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

import CoreGraphics
import Foundation
#if os(iOS)
  import Accelerate
  import AVFoundation
  import UIKit
  import VideoToolbox
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
    private let pendingPipFrame = LatestPictureInPictureFrame<(pixel: CVPixelBuffer, source: String)>()
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
    // Set once AVKit refuses a native HDR sample; the SDR copy takes over.
    private var hdrPipRejected = false
    private var hdrPipRejectionObserver: NSObjectProtocol?
    private var loggedHdrPipSource = false
    // Platform views can overlap while entering/leaving fullscreen. Keep all
    // live views, and replay the last frame when a paused view is attached.
    // These presentation fields are only accessed on the main thread.
    private let hdrPlatformViews = NSHashTable<HDRMetalVideoPlatformView>.weakObjects()
    private var hdrPlatformViewOrder: [ObjectIdentifier] = []
    private weak var presentingHdrView: HDRMetalVideoPlatformView?
    private var hdrFrame: (pixel: CVPixelBuffer, colorSpace: Int32, minLuminance: Float, maxLuminance: Float)?
    /// Decoded Dolby Vision frame and libmpv's OSD/subtitle overlay, while the
    /// system compositor presents the video (`iosurface-hdr+dovi`).
    private var dolbyFrame: (video: CVPixelBuffer, overlay: CVPixelBuffer)?
    private var loggedDolbyVisionUnsupported = false
    private var lastDolbyVisionSkipReason: String?
    private let systemSupportsDolbyVision = AVPlayer.availableHDRModes.contains(.dolbyVision)
    // Failure is scoped to this media/track. Do not keep retrying a rejected
    // sample layer; a different source can negotiate the native path again.
    private var dolbyVisionSource: String?
    private var dolbyVisionSourceProfile: Int?
    private var dolbyVisionRejectionReason: String?
    private var loggedDolbyVisionFrame = false
    private var lastDolbyVisionFrameDescription: [String: Any] = [:]
    // Worker-owned current native frame, including a paused PiP handoff.
    private var currentDolbyVisionFrame: CVPixelBuffer?
    private var loggedDolbyPipCompositionFailure = false
    private var usedDolbyPipComposition = false
    private var inlineFrameSource: String?
    // Accessed on the main thread, like dolbyFrame and the presentation views.
    private var dolbyFrameSource: String?
    private var dolbyFrameDescription: [String: Any] = [:]
    private var lastInlineHdrActive = false
    private var potentialHdrHeadroom: Double = 1
    // Opt-in device diagnostics; no per-frame clock reads in ordinary builds.
    private let measuresRenderTime = ProcessInfo.processInfo.environment["BOTA_IOS_RENDER_PROBE"] == "1"
    private var renderTimes: [Double] = []
    private var recoveredGpuSource: String?
    private var gpuRecoveryCount = 0
    private let screenPixels = UIScreen.main.nativeBounds.size
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
          let presentationChanged = that.pipPolicy.presenting != active
          if presentationChanged && !active && that.usedDolbyPipComposition {
            // A PiP layer rejecting the composed HDR sample must not disable
            // the separate inline Dolby layer after the window is closed.
            that.hdrPipRejected = false
            that.usedDolbyPipComposition = false
          }
          that.pipFrameDelivery = frames
          if !frames {
            that.pendingPipFrame.discard()
            that.pipFrameSource = .undecided
            that.hdrPipFrameConverter?.reset()
            that.loggedHdrPipSource = false
            (that.texture as? TextureIOSurface)?.retainsPictureInPictureFrames = false
          }
          that.pipPolicy.presenting = active
          that.updatePictureInPictureRenderer()
          // Paused playback has no new frame to trigger the output switch.
          if presentationChanged && that.pipPolicy.appIsActive && that.usesDolbyVisionPassthrough {
            that._updateCallback()
          }
          if requestFrame && that.pipPolicy.appIsActive && that.pipFrameDelivery {
            that.deliverPictureInPictureFrame(force: true)
          }
        }
      }

      hdrPipRejectionObserver = NotificationCenter.default.addObserver(
        forName: Notification.Name("bota.mobile-pip-hdr-rejected"), object: nil, queue: .main
      ) { [weak self] event in
        guard let that = self,
          event.userInfo?["identity"] as? String == String(Int(bitPattern: that.handle)) else { return }
        that.worker.enqueue { [weak that] in
          guard let that = that, !that.disposed, !that.hdrPipRejected else { return }
          NSLog("VideoOutput: AVKit rejected native HDR PiP samples; using the SDR copy")
          that.hdrPipRejected = true
          that.pendingPipFrame.discard()
          that.pipFrameSource = .undecided
          (that.texture as? TextureIOSurface)?.retainsPictureInPictureFrames = false
          if that.currentDolbyVisionFrame != nil, that.pipPolicy.appIsActive {
            that._updateCallback()
          }
          if that.pipFrameDelivery && that.pipPolicy.appIsActive {
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
      if let observer = hdrPipRejectionObserver { NotificationCenter.default.removeObserver(observer) }
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
      return renderBackend == "iosurface-hdr" || usesDolbyVisionPassthrough
    #else
      return false
    #endif
  }

  /// Automatic native Dolby Vision: VideoToolbox frames that carry per-frame
  /// Dolby Vision metadata bypass libmpv's compositor (and therefore its
  /// equalizer, shaders, zoom and tone mapping); libmpv draws only the OSD
  /// and subtitles above them.
  private var usesDolbyVisionPassthrough: Bool {
    #if os(iOS)
      return renderBackend == "iosurface-hdr+dovi"
    #else
      return false
    #endif
  }

  #if os(iOS)
    func matchesTextureId(_ id: Int64) -> Bool { textureId == id }

    var hdrState: [String: Any] {
      var headroom = 1.0
      var currentHeadroom = 1.0
      if #available(iOS 16.0, *) {
        headroom = Double(UIScreen.main.potentialEDRHeadroom)
        currentHeadroom = Double(UIScreen.main.currentEDRHeadroom)
      }
      let display = presentingHdrView?.surfaceView.displayState() ?? [:]
      let dolby = display["dolbyVision"] as? [String: Any]
      let eligible = display["eligible"] as? Bool == true
      let color = display["frameColorSpace"] as? Int32 ?? 0
      let mode: String
      if dolbyFrame != nil, eligible, dolby?["status"] as? Int == 1,
        (dolby?["rpuBytes"] as? Int ?? 0) > 0 { mode = "native-dolby-vision" }
      else if lastInlineHdrActive, eligible, display["hasFrame"] as? Bool == true,
        display["wantsEDR"] as? Bool == true, color == 1 { mode = "hdr10-edr" }
      else if lastInlineHdrActive, eligible, display["hasFrame"] as? Bool == true,
        display["wantsEDR"] as? Bool == true, color == 2 { mode = "hlg-edr" }
      else if !lastInlineHdrActive, inlineTexture.latestFrame != nil { mode = "sdr" }
      else { mode = "pending" }
      return ["requested": usesHdrSurface, "available": usesHdrSurface && headroom > 1,
              "active": lastInlineHdrActive, "potentialHeadroom": headroom,
              "currentHeadroom": currentHeadroom, "outputMode": mode,
              "availableHDRModes": AVPlayer.availableHDRModes.rawValue,
              "outputColorSpace": mode == "native-dolby-vision" || mode == "pending"
                ? NSNull() : (mode == "sdr" ? 0 : color) as Any,
              "rpuBytes": dolby?["rpuBytes"] ?? 0, "display": display,
              "colorSpace": hdrFrame?.colorSpace ?? 0,
              "dolbyVisionRequested": usesDolbyVisionPassthrough,
              "dolbyVisionSupported": systemSupportsDolbyVision,
              "dolbyVision": dolbyFrame != nil,
              "dolbyVisionFrame": dolbyFrameDescription]
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
        stats["pictureInPicture"] = [
          "delivery": self.pipFrameDelivery, "presenting": self.pipPolicy.presenting,
          "draining": self.drainsPictureInPictureFrames,
          "source": String(describing: self.pipFrameSource),
          "nativeHdr": self.loggedHdrPipSource, "hdrRejected": self.hdrPipRejected,
          "hdrComposition":
            (self.texture as? TextureIOSurface)?.supportsHdrPictureInPictureComposition ?? false,
        ] as [String: Any]
        stats["views"] = views
        stats["sourceDolbyVisionProfile"] = self.dolbyVisionSourceProfile.map { $0 as Any } ?? NSNull()
        stats["subtitleTrack"] = self.stringProperty("sid").map { $0 as Any } ?? NSNull()
        stats["dolbyVisionRejection"] = self.dolbyVisionRejectionReason ?? NSNull()
        stats["gpuRecoveries"] = self.gpuRecoveryCount
        if self.measuresRenderTime {
          stats["outputSamples"] = (self.texture as? TextureIOSurface)?.diagnosticFrameSummary() ?? [:]
          stats["hardwareCodecs"] = [
            "h264": VTIsHardwareDecodeSupported(0x61766331),
            "hevc": VTIsHardwareDecodeSupported(0x68766331),
            "dolbyHevc": VTIsHardwareDecodeSupported(0x64766831),
            "vp9": VTIsHardwareDecodeSupported(0x76703039),
            "av1": VTIsHardwareDecodeSupported(0x61763031),
          ]
        }
        if reset { self.renderTimes.removeAll(keepingCapacity: true) }
        DispatchQueue.main.async { completion(stats) }
      }
    }

    func probeGpuRecovery(completion: @escaping (Bool) -> Void) {
      guard measuresRenderTime else { completion(false); return }
      worker.enqueue { [weak self] in
        guard let self = self, !self.disposed else {
          DispatchQueue.main.async { completion(false) }
          return
        }
        let injected = (self.texture as? TextureIOSurface)?.probeDeviceFailure() == true
        let recovered = injected && self.recoverFailedGpuRenderer()
        DispatchQueue.main.async { completion(recovered) }
      }
    }

    func attachHdrView(_ view: HDRMetalVideoPlatformView) {
      hdrPlatformViews.add(view)
      let identity = ObjectIdentifier(view)
      hdrPlatformViewOrder.append(identity)
      view.surfaceView.onPresentationEligibilityChanged = { [weak self] in
        self?.displayHdrFrame()
      }
      view.surfaceView.onDolbyVisionFailure = { [weak self] reason in
        guard let self = self, self.dolbyFrame != nil else { return }
        let source = self.dolbyFrameSource
        self.dolbyFrame = nil
        for candidate in self.hdrPlatformViews.allObjects { candidate.surfaceView.endDolbyVision() }
        self.worker.enqueue { [weak self] in
          guard let self = self, !self.disposed, self.dolbyVisionSource == source else { return }
          self.dolbyVisionRejectionReason = reason
          self.currentDolbyVisionFrame = nil
          // Redraw the retained decoded frame through mpv, including while
          // paused. P5 needs its RPU reshaping, not an HDR10-only retag.
          self._updateCallback()
        }
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
      if let frame = dolbyFrame {
        view.surfaceView.displayDolbyVision(video: frame.video, overlay: frame.overlay)
      } else if let frame = hdrFrame {
        view.surfaceView.display(frame.pixel, colorSpace: frame.colorSpace,
          minLuminance: frame.minLuminance, maxLuminance: frame.maxLuminance)
      } else {
        view.surfaceView.endDolbyVision()
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
        if let self = self, !self.disposed {
          // System artwork is a static cover for the media. Use the already
          // composited image (with P5 reshaping), without consuming a pending
          // video frame just to capture a cover or encoding raw IPT planes.
          if self.currentDolbyVisionFrame != nil && self.inlineFrameSource != self.dolbyVisionSource {
            data = nil
          } else if let frame = self.inlineTexture.latestFrame {
            if CVPixelBufferGetPixelFormatType(frame) == kCVPixelFormatType_32BGRA {
              data = VideoArtwork.encode(frame)
            } else if self.currentDolbyVisionFrame != nil,
              let renderer = self.texture as? TextureIOSurface {
              if self.hdrPipFrameConverter == nil { self.hdrPipFrameConverter = HDRPictureInPictureFrameConverter() }
              if let copy = self.hdrPipFrameConverter?.convert(frame, colorSpace: renderer.currentColorSpace) {
                data = VideoArtwork.encode(copy)
              } else { data = nil }
            } else { data = nil }
          } else { data = nil }
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
      if recoverFailedGpuRenderer() { return }
    #endif
    let logicalSize = videoSize
    #if os(iOS)
      var size = logicalSize
      if pipRendering && max(size.width, size.height) > 640 {
        let ratio = 640 / max(size.width, size.height)
        size = CGSize(width: max(2, (size.width * ratio).rounded(.down)),
          height: max(2, (size.height * ratio).rounded(.down)))
      } else if width == nil && height == nil {
        // An explicit size is a caller's request (shader upscaling targets).
        size = IOSRenderTargetPolicy.size(for: size, screen: screenPixels)
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
      if renderDolbyVisionFrame(size, logicalSize: logicalSize) { return }
      currentDolbyVisionFrame = nil
      let renderStart = measuresRenderTime ? CFAbsoluteTimeGetCurrent() : 0
      guard texture.renderVideoFrame(size, needsDecodedFrame: pipHandoff.needsDecodedFrame),
        let frame = texture.copyPixelBuffer()?.takeRetainedValue() else {
        _ = recoverFailedGpuRenderer()
        return
      }
      if measuresRenderTime, renderTimes.count < 3600 {
        renderTimes.append((CFAbsoluteTimeGetCurrent() - renderStart) * 1000)
      }
      let firstAfterHandoff = pipHandoff.needsDecodedFrame
      pipHandoff.didPublishFrame()
      displayedSize = logicalSize
      inlineTexture.publish(frame)
      inlineFrameSource = playbackSource()
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
    /// The kind of raw decoder sample AVKit may present, or nil when the
    /// picture needs mpv's compositor (subtitles, equalizer, geometry, DV P5).
    private func decodedPictureInPictureKind() -> DecodedPictureInPictureColorPolicy.Kind? {
      guard renderBackend == "iosurface+decoded-pip" || usesHdrSurface else { return nil }
      // A direct sample is before mpv's OSD and output transform.
      for property in ["sid", "secondary-sid"] {
        guard let selected = mpv_get_property_string(handle, property) else { return nil }
        let disabled = String(cString: selected) == "no"
        mpv_free(selected)
        if !disabled { return nil }
      }
      for property in ["brightness", "contrast", "gamma", "hue", "saturation", "video-zoom", "panscan"] {
        var value = 0.0
        guard mpv_get_property(handle, property, MPV_FORMAT_DOUBLE, &value) >= 0, value == 0 else { return nil }
      }
      func videoParameter(_ property: String) -> String? {
        guard let value = mpv_get_property_string(handle, "video-out-params/\(property)") else { return nil }
        defer { mpv_free(value) }
        return String(cString: value).lowercased()
      }
      // The inline target records what the user is actually being shown; an
      // HDR source mapped to SDR must stay mapped in the system window too.
      let hdrOutputActive = usesHdrSurface && !hdrPipRejected &&
        ((texture as? TextureIOSurface)?.currentColorSpace ?? 0) != 0
      guard let kind = DecodedPictureInPictureColorPolicy.kind(
        transfer: videoParameter("gamma"), primaries: videoParameter("primaries"),
        matrix: videoParameter("colormatrix"), hdrOutputActive: hdrOutputActive),
        MPVHelpers.getVideoOutParams(handle).rotate == 0 else { return nil }
      return kind
    }

    /// The transfer to present a software-composited frame with, while the
    /// inline player is showing HDR. Subtitles are then mapped by libmpv.
    private func compositedHdrPictureInPictureKind() -> DecodedPictureInPictureColorPolicy.Kind? {
      guard usesHdrSurface, !hdrPipRejected, let renderer = texture as? TextureIOSurface,
        renderer.supportsHdrPictureInPictureComposition,
        let kind = PictureInPictureColorTags.kind(colorSpace: renderer.currentColorSpace),
        let matrix = mpv_get_property_string(handle, "video-out-params/colormatrix") else { return nil }
      defer { mpv_free(matrix) }
      // Dolby Vision profile 5 needs the GPU path's reshaping to be correct.
      return String(cString: matrix).lowercased().hasPrefix("bt.2020") ? kind : nil
    }

    private func isSupportedDecodedPictureInPictureFrame(
      _ pixel: CVPixelBuffer, kind: DecodedPictureInPictureColorPolicy.Kind) -> Bool {
      let format = CVPixelBufferGetPixelFormatType(pixel)
      if kind == .sdr {
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
          format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else { return false }
        if #available(iOS 11.0, *),
          let transfer = CVBufferGetAttachment(pixel, kCVImageBufferTransferFunctionKey, nil)?.takeUnretainedValue(),
          CFEqual(transfer, kCVImageBufferTransferFunction_ITU_R_2100_HLG) ||
            CFEqual(transfer, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ) {
          return false
        }
      } else {
        guard HDRPictureInPictureTags.isDecodedHdrFormat(format) else { return false }
      }
      let width = CVPixelBufferGetWidth(pixel), height = CVPixelBufferGetHeight(pixel)
      guard height > 0, displayedSize.width > 0, displayedSize.height > 0 else { return false }
      let sourceAspect = Double(width) / Double(height)
      return abs(sourceAspect - Double(displayedSize.width / displayedSize.height)) < 0.01
    }

    private func drainPictureInPictureFrame() {
      guard let renderer = texture as? TextureIOSurface else { return }
      if usesDolbyVisionPassthrough { refreshDolbyVisionSource(renderer) }
      if deliverCompositedDolbyPipFrame(renderer, current: false, handoff: false) { return }
      if pipFrameDelivery, permitsDolbyVisionSamples(),
        let peek = renderer.decodedPictureInPictureFrame(dequeue: false).pixel,
        DolbyVisionFrame.hasMetadata(peek) {
        let next = renderer.decodedPictureInPictureFrame(dequeue: true)
        if next.supported && next.pixel == nil { return }
        if let pixel = next.pixel,
          let frame = DolbyVisionFrame.prepare(pixel, profile: dolbyVisionSourceProfile,
            transfer: stringProperty("video-out-params/gamma")?.lowercased()) {
          currentDolbyVisionFrame = frame
          pipFrameSource = .decoded
          enqueuePictureInPictureFrame(frame, handoff: false)
          return
        }
      }
      if pipFrameDelivery, let kind = decodedPictureInPictureKind(),
        let peek = renderer.decodedPictureInPictureFrame(dequeue: false).pixel,
        isSupportedDecodedPictureInPictureFrame(peek, kind: kind) {
        let next = renderer.decodedPictureInPictureFrame(dequeue: true)
        if next.supported {
          if let frame = next.pixel, isSupportedDecodedPictureInPictureFrame(frame, kind: kind) {
            pipFrameSource = .decoded
            enqueueDecodedPictureInPictureFrame(frame, kind: kind, handoff: false)
          } else if next.pixel != nil {
            // A format switch was consumed on this callback. Compose the
            // current frame without restarting the decoder or dropping text.
            let hdr = compositedHdrPictureInPictureKind()
            let composed = renderer.compositedPictureInPictureFrame(videoSize, deliver: true, hdr: hdr)
            if let frame = composed.pixel {
              if let hdr = hdr { logHdrPictureInPictureSource("software compositor", kind: hdr) }
              pipFrameSource = .composited
              enqueuePictureInPictureFrame(frame, handoff: false)
            }
          }
          return
        }
      }
      let hdr = compositedHdrPictureInPictureKind()
      let next = renderer.compositedPictureInPictureFrame(videoSize, deliver: pipFrameDelivery, hdr: hdr)
      if let frame = next.pixel {
        if let hdr = hdr { logHdrPictureInPictureSource("software compositor", kind: hdr) }
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

    /// A lost Vulkan/Metal device cannot be repaired by clearing its frame
    /// queue. Recreate the renderer on the same mpv player; track selection,
    /// audio clock, subtitles and user options stay on that player.
    private func recoverFailedGpuRenderer() -> Bool {
      guard !disposed, pipPolicy.appIsActive, !pipRendering,
        let renderer = texture as? TextureIOSurface, renderer.deviceFailed else { return false }
      let source = playbackSource()
      guard recoveredGpuSource != source else { return false }
      recoveredGpuSource = source
      gpuRecoveryCount += 1
      let videoId = stringProperty("vid")
      var paused: Int32 = 0
      _ = mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &paused)
      NSLog("VideoOutput: rebuilding failed iOS GPU renderer (attempt %d)", gpuRecoveryCount)
      currentDolbyVisionFrame = nil
      dolbyVisionRejectionReason = nil
      releasePictureInPictureRenderContext?()
      texture = nil
      currentSize = .zero
      createTexture(hardware: enableHardwareAcceleration)
      if let videoId = videoId, videoId != "no" {
        _ = mpv_set_property_string(handle, "vid", videoId)
      }
      _ = mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &paused)
      return true
    }

    private func stringProperty(_ name: String) -> String? {
      guard let value = mpv_get_property_string(handle, name) else { return nil }
      defer { mpv_free(value) }
      return String(cString: value)
    }

    private func playbackSource() -> String {
      "\(stringProperty("path") ?? "")|\(stringProperty("vid") ?? "")"
    }

    private func dolbyVisionNeedsPictureProcessing() -> Bool {
      for property in ["brightness", "contrast", "gamma", "hue", "saturation",
                       "video-zoom", "video-pan-x", "video-pan-y", "video-align-x",
                       "video-align-y", "panscan"] {
        var value = 0.0
        if mpv_get_property(handle, property, MPV_FORMAT_DOUBLE, &value) < 0 || value != 0 { return true }
      }
      if MPVHelpers.getVideoOutParams(handle).rotate != 0 { return true }
      if let aspect = stringProperty("video-aspect-override").flatMap(Double.init), aspect > 0 { return true }
      for property in ["glsl-shaders", "vf"] {
        if let value = stringProperty(property), !value.isEmpty { return true }
      }
      return stringProperty("deband") == "yes" || stringProperty("interpolation") == "yes"
    }

    private func permitsDolbyVisionSamples() -> Bool {
      IOSDolbyVisionOutputPolicy.permits(enabled: usesDolbyVisionPassthrough,
        systemSupported: systemSupportsDolbyVision, hint: stringProperty("target-colorspace-hint"),
        profile: dolbyVisionSourceProfile, needsPictureProcessing: dolbyVisionNeedsPictureProcessing(),
        rejected: dolbyVisionRejectionReason != nil || hdrPipRejected)
    }

    private func shouldCompositeDolbyPip(_ renderer: TextureIOSurface) -> Bool {
      let permitted = IOSDolbyVisionOutputPolicy.permits(enabled: usesDolbyVisionPassthrough,
        systemSupported: systemSupportsDolbyVision, hint: stringProperty("target-colorspace-hint"),
        profile: dolbyVisionSourceProfile, needsPictureProcessing: dolbyVisionNeedsPictureProcessing(),
        rejected: dolbyVisionRejectionReason != nil)
      return IOSDolbyVisionOutputPolicy.composesPictureInPicture(
        framesArmed: pipFrameDelivery, nativePermitted: permitted,
        compositionSupported: renderer.supportsDolbyPictureInPictureComposition,
        primary: stringProperty("sid"), primaryVisible: stringProperty("sub-visibility"),
        secondary: stringProperty("secondary-sid"), secondaryVisible: stringProperty("secondary-sub-visibility"))
    }

    /// Keep the same decoder, RPU and subtitle clock. Only PiP's presentation
    /// becomes PQ/EDR; never send raw P5 pixels with ordinary HDR color tags.
    private func deliverCompositedDolbyPipFrame(_ renderer: TextureIOSurface,
                                               current: Bool, handoff: Bool) -> Bool {
      guard shouldCompositeDolbyPip(renderer) else { return false }
      let started = measuresRenderTime ? CFAbsoluteTimeGetCurrent() : 0
      let result = renderer.compositedDolbyPictureInPictureFrame(videoSize, current: current)
      if measuresRenderTime, renderTimes.count < 3600 {
        renderTimes.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
      }
      guard let pixel = result.pixel else {
        if !result.supported && !loggedDolbyPipCompositionFailure {
          loggedDolbyPipCompositionFailure = true
          NSLog("VideoOutput: Dolby PiP composition unavailable; retaining the last valid PiP frame")
        }
        return true
      }
      loggedDolbyPipCompositionFailure = false
      usedDolbyPipComposition = true
      var output = pixel
      if hdrPipRejected {
        if hdrPipFrameConverter == nil { hdrPipFrameConverter = HDRPictureInPictureFrameConverter() }
        guard let sdr = hdrPipFrameConverter?.convert(pixel, colorSpace: 1) else { return true }
        output = sdr
      } else {
        logHdrPictureInPictureSource("Dolby RPU and subtitle compositor", kind: .pq)
      }
      pipFrameSource = .composited
      lastPipPreviewFrame = CFAbsoluteTimeGetCurrent()
      enqueuePictureInPictureFrame(output, handoff: handoff)
      return true
    }

    private func refreshDolbyVisionSource(_ renderer: TextureIOSurface) {
      let source = playbackSource()
      if source != dolbyVisionSource {
        dolbyVisionSource = source
        dolbyVisionSourceProfile = stringProperty("current-tracks/video/dolby-vision-profile").flatMap(Int.init)
        dolbyVisionRejectionReason = nil
        loggedDolbyVisionFrame = false
        lastDolbyVisionFrameDescription = [:]
        currentDolbyVisionFrame = nil
        loggedDolbyPipCompositionFailure = false
        usedDolbyPipComposition = false
      }
      // A demuxer's track metadata can arrive after its first frame. Retry
      // only for actual Dolby frames rather than caching unknown forever.
      if dolbyVisionSourceProfile == nil,
        let pixel = renderer.decodedPictureInPictureFrame(dequeue: false).pixel,
        DolbyVisionFrame.hasMetadata(pixel) {
        dolbyVisionSourceProfile = stringProperty("current-tracks/video/dolby-vision-profile").flatMap(Int.init)
      }
    }

    /// Present the next frame natively when automatic HDR output permits it.
    /// Forced SDR, picture processing and native failures use the compositor.
    private func renderDolbyVisionFrame(_ size: CGSize, logicalSize: CGSize) -> Bool {
      guard usesDolbyVisionPassthrough, pipPolicy.appIsActive, !pipRendering,
        !pipHandoff.needsDecodedFrame, let renderer = texture as? TextureIOSurface else { return false }
      refreshDolbyVisionSource(renderer)
      if pipPolicy.presenting && shouldCompositeDolbyPip(renderer) { return false }
      let source = dolbyVisionSource ?? ""
      let profile = dolbyVisionSourceProfile
      guard systemSupportsDolbyVision, [5, 8].contains(profile ?? 0),
        dolbyVisionRejectionReason == nil, !hdrPipRejected,
        ["auto", "yes"].contains(stringProperty("target-colorspace-hint") ?? "") else { return false }
      let transfer = stringProperty("video-out-params/gamma")?.lowercased()
      guard permitsDolbyVisionSamples() else { return false }
      guard renderer.supportsOverlayOnlyRendering else {
        if !loggedDolbyVisionUnsupported {
          loggedDolbyVisionUnsupported = true
          NSLog("VideoOutput: libmpv lacks overlay-only rendering; Dolby Vision stays composited")
        }
        return false
      }
      // Decide from the frame already on screen: the first frame of a source
      // is composited, and so is everything after a switch to a non-DV source.
      let onScreen = renderer.decodedPictureInPictureFrame(dequeue: false)
      guard let current = onScreen.pixel, DolbyVisionFrame.hasMetadata(current) else {
        let reason = onScreen.pixel == nil
          ? (onScreen.supported ? "no decoded frame" : "frame is not a VideoToolbox surface")
          : "decoded frame has no Dolby Vision metadata"
        if reason != lastDolbyVisionSkipReason {
          lastDolbyVisionSkipReason = reason
          NSLog("VideoOutput: Dolby Vision passthrough idle: %@", reason)
        }
        return false
      }
      lastDolbyVisionSkipReason = nil
      guard let frame = renderer.renderDolbyVisionFrame(size) else { return false }
      let decoderDescription = loggedDolbyVisionFrame ? [:] : DolbyVisionFrame.describe(frame.video)
      guard let video = DolbyVisionFrame.prepare(frame.video, profile: profile, transfer: transfer) else { return false }
      if !loggedDolbyVisionFrame {
        loggedDolbyVisionFrame = true
        lastDolbyVisionFrameDescription = ["profile": profile ?? 0,
          "decoder": decoderDescription, "display": DolbyVisionFrame.describe(video)]
        NSLog("VideoOutput: native Dolby Vision metadata %@", String(describing: lastDolbyVisionFrameDescription))
      }
      displayedSize = logicalSize
      currentDolbyVisionFrame = video
      notifyDolbyVisionFrame((video, frame.overlay), source: source, description: lastDolbyVisionFrameDescription)
      // AVKit maps the same Dolby Vision samples; its preview has no overlay.
      let now = CFAbsoluteTimeGetCurrent()
      if pipFrameDelivery, pipPolicy.presenting || now - lastPipPreviewFrame >= 0.5 {
        if deliverCompositedDolbyPipFrame(renderer, current: true, handoff: false) { return true }
        lastPipPreviewFrame = now
        pipFrameSource = .decoded
        enqueuePictureInPictureFrame(video, handoff: false)
      }
      return true
    }

    private func notifyDolbyVisionFrame(_ frame: (video: CVPixelBuffer, overlay: CVPixelBuffer),
                                        source: String, description: [String: Any]) {
      guard displayedSize != .zero else { return }
      let size = displayedSize
      DispatchQueue.main.sync { [weak self] in
        guard let self = self, !self.disposed, self.textureId >= 0,
          UIApplication.shared.applicationState == .active else { return }
        if self.lastInlineSize != size || !self.lastInlineHdrActive {
          self.lastInlineSize = size
          self.lastInlineHdrActive = true
          // The native platform view hosts the system-presented video.
          self.textureUpdateCallback(self.textureId, size, true)
        }
        self.dolbyFrame = frame
        self.dolbyFrameSource = source
        self.dolbyFrameDescription = description
        self.displayHdrFrame()
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
        let leftDolbyVision = self.dolbyFrame != nil
        self.dolbyFrame = nil
        self.dolbyFrameSource = nil
        if hdrActive {
          if let frame = frame {
            self.hdrFrame = (frame, colorSpace, minimum, peak)
            self.displayHdrFrame()
          }
        } else {
          self.hdrFrame = nil
          if leftDolbyVision { self.displayHdrFrame() }
          self.registry.textureFrameAvailable(self.textureId)
        }
      }
    }

    private func deliverPictureInPictureFrame(force: Bool = false, handoff: Bool = false) {
      // Automatic PiP only takes a preview twice per second when armed. A
      // live foreground PiP needs every frame, but never resizes mpv's output.
      let previewTime = CFAbsoluteTimeGetCurrent()
      guard pipFrameDelivery, force || pipPolicy.presenting || previewTime - lastPipPreviewFrame >= 0.5 else { return }
      if usesDolbyVisionPassthrough, let renderer = texture as? TextureIOSurface {
        refreshDolbyVisionSource(renderer)
        if currentDolbyVisionFrame != nil &&
          deliverCompositedDolbyPipFrame(renderer, current: true, handoff: handoff) { return }
      }
      if let frame = currentDolbyVisionFrame, permitsDolbyVisionSamples() {
        pipFrameSource = .decoded
        lastPipPreviewFrame = previewTime
        enqueuePictureInPictureFrame(frame, handoff: handoff)
        return
      }
      guard let pixel = inlineTexture.latestFrame else { return }
      if let kind = decodedPictureInPictureKind() {
        if let renderer = texture as? TextureIOSurface,
          let decoded = renderer.decodedPictureInPictureFrame(dequeue: false).pixel,
          isSupportedDecodedPictureInPictureFrame(decoded, kind: kind) {
          if pipFrameSource != .decoded { NSLog("VideoOutput: PiP using decoder-owned VideoToolbox frames") }
          pipFrameSource = .decoded
          lastPipPreviewFrame = previewTime
          enqueueDecodedPictureInPictureFrame(decoded, kind: kind, handoff: handoff)
          return
        }
      }
      pipFrameSource = .composited
      if CVPixelBufferGetPixelFormatType(pixel) != kCVPixelFormatType_32BGRA {
        guard let renderer = texture as? TextureIOSurface else { return }
        // The inline HDR target already holds video, ASS and bitmap subtitles
        // in PQ/HLG. Hand AVKit that same IOSurface instead of an SDR copy.
        if !hdrPipRejected,
          CVPixelBufferGetPixelFormatType(pixel) == kCVPixelFormatType_ARGB2101010LEPacked,
          let kind = PictureInPictureColorTags.kind(colorSpace: renderer.currentColorSpace) {
          HDRPictureInPictureTags.apply(pixel, kind: kind, yuv: false)
          renderer.retainsPictureInPictureFrames = true
          logHdrPictureInPictureSource("composited 10-bit target", kind: kind)
          lastPipPreviewFrame = previewTime
          enqueuePictureInPictureFrame(pixel, handoff: handoff)
          return
        }
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

    private func logHdrPictureInPictureSource(_ source: String,
                                              kind: DecodedPictureInPictureColorPolicy.Kind) {
      guard !loggedHdrPipSource else { return }
      loggedHdrPipSource = true
      NSLog("VideoOutput: PiP presenting native %@ from the %@", kind == .pq ? "HDR10" : "HLG", source)
    }

    private func enqueueDecodedPictureInPictureFrame(
      _ pixel: CVPixelBuffer, kind: DecodedPictureInPictureColorPolicy.Kind, handoff: Bool) {
      if kind != .sdr {
        // VideoToolbox can leave the transfer attachment off when the stream
        // carries it only in the container; AVKit would then show HDR as SDR.
        HDRPictureInPictureTags.apply(pixel, kind: kind, yuv: true)
        logHdrPictureInPictureSource("VideoToolbox decoder", kind: kind)
      }
      enqueuePictureInPictureFrame(pixel, handoff: handoff)
    }

    private func enqueuePictureInPictureFrame(_ pixel: CVPixelBuffer, handoff: Bool) {
      let source = pipFrameSource == .decoded ? "decoded" : pipFrameSource == .composited ? "composited" : "unknown"
      guard pendingPipFrame.store((pixel, source), handoff: handoff) else { return }
      let identity = String(Int(bitPattern: handle))
      DispatchQueue.main.async { [weak self] in
        guard let frame = self?.pendingPipFrame.take() else { return }
        NotificationCenter.default.post(name: Notification.Name("bota.mobile-video-frame"), object: nil,
          userInfo: ["identity": identity, "pixelBuffer": frame.frame.pixel,
            "source": frame.frame.source, "renderHandoff": frame.handoff])
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

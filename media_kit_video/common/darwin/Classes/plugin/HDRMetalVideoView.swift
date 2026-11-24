import CoreVideo
import Flutter
import IOSurface
import Metal
import QuartzCore
import UIKit

#if SWIFT_PACKAGE
  import Mpv
#endif

/// Native EDR presentation surface for libmpv's packed 10-bit IOSurface output.
final class HDRMetalSurfaceView: UIView {
  private typealias Frame = (pixel: CVPixelBuffer, colorSpace: Int32, minLuminance: Float, maxLuminance: Float)
  override class var layerClass: AnyClass { CAMetalLayer.self }

  private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private var currentFrame: Frame?
  private let presentationQueue = DispatchQueue(label: "media_kit_video.hdr-presentation", qos: .userInteractive)
  private let pendingFrame = LatestPictureInPictureFrame<Frame>()
  private let presentationActivity = PictureInPictureAppActivity()
  private var inactiveObserver: NSObjectProtocol?
  private var configuredColorSpace: Int32?
  private var configuredLuminance: (Float, Float)?
  private let measuresRenderTime = ProcessInfo.processInfo.environment["BOTA_IOS_RENDER_PROBE"] == "1"
  private var submitTimes: [Double] = []
  private var gpuTimes: [Double] = []
  var onPresentationEligibilityChanged: (() -> Void)?
  var onDolbyVisionFailure: ((String) -> Void)?
  private var lastPresentationEligibility = false
  private var presentationEnabled = false
  private var dolbyVisionView: DolbyVisionPassthroughView?
  var isPresentingDolbyVision: Bool { dolbyVisionView?.isHidden == false }

  var isEligibleForPresentation: Bool {
    guard window != nil, bounds.width > 0, bounds.height > 0 else { return false }
    var ancestor: UIView? = self
    while let view = ancestor {
      if view.isHidden || view.alpha <= 0 { return false }
      ancestor = view.superview
    }
    return true
  }

  func setPresentationEnabled(_ enabled: Bool) {
    presentationEnabled = enabled
    if !enabled {
      presentationActivity.isActive = false
      pendingFrame.discard()
      currentFrame = nil
      endDolbyVision()
    }
  }

  private func updatePresentationEligibility() {
    let eligible = isEligibleForPresentation
    if eligible != lastPresentationEligibility {
      lastPresentationEligibility = eligible
      onPresentationEligibilityChanged?()
    }
  }

  func compositionState() -> [String: Any] {
    var ancestors: [[String: Any]] = []
    var current: UIView? = self
    while let view = current {
      ancestors.append(["class": String(describing: type(of: view)),
        "frame": String(describing: view.frame), "bounds": String(describing: view.bounds),
        "alpha": view.alpha, "hidden": view.isHidden,
        "transform": String(describing: view.transform),
        "children": view.subviews.map { child in
          ["class": String(describing: type(of: child)), "frame": String(describing: child.frame),
           "interactive": child.isUserInteractionEnabled,
           "children": child.subviews.map { String(describing: type(of: $0)) } ] as [String: Any]
        }])
      current = view.superview
    }
    let display = displayState()
    return ["ancestors": ancestors, "window": window != nil,
      "hasFrame": currentFrame != nil, "drawableSize": String(describing: metalLayer.drawableSize),
      "display": display, "dolbyVision": display["dolbyVision"] ?? NSNull()]
  }

  func displayState() -> [String: Any] {
    let dolby: [String: Any]? = isPresentingDolbyVision ? dolbyVisionView?.stats() : nil
    var display: [String: Any] = ["eligible": isEligibleForPresentation && presentationEnabled,
      "hasFrame": dolby != nil || currentFrame != nil,
      "frameColorSpace": currentFrame.map { $0.colorSpace as Any } ?? NSNull(),
      "pixelFormat": currentFrame.map { CVPixelBufferGetPixelFormatType($0.pixel) as Any } ?? NSNull(),
      "layerColorSpace": metalLayer.colorspace?.name.map { $0 as String } ?? NSNull(),
      "wantsEDR": NSNull()]
    if #available(iOS 16.0, *), dolby == nil {
      display["wantsEDR"] = metalLayer.wantsExtendedDynamicRangeContent
    }
    if let dolby = dolby { display["dolbyVision"] = dolby }
    return display
  }

  func renderStats(reset: Bool) -> [String: Any] {
    let stats: [String: Any] = ["submit": IOSRenderTiming.summary(submitTimes), "gpu": IOSRenderTiming.summary(gpuTimes)]
    if reset { submitTimes.removeAll(keepingCapacity: true); gpuTimes.removeAll(keepingCapacity: true) }
    return stats
  }

  override init(frame: CGRect) {
    guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue() else {
      fatalError("Metal is required for the iOS HDR video surface")
    }
    self.device = device
    self.queue = queue
    super.init(frame: frame)
    isOpaque = true
    backgroundColor = .black
    metalLayer.device = device
    metalLayer.pixelFormat = .bgr10a2Unorm
    metalLayer.framebufferOnly = false
    metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    inactiveObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.presentationActivity.isActive = false
      self?.pendingFrame.discard()
    }
  }

  deinit {
    presentationActivity.isActive = false
    if let inactiveObserver = inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver) }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    updatePresentationEligibility()
    drawFrame()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updatePresentationEligibility()
    drawFrame()
  }

  func display(_ pixelBuffer: CVPixelBuffer, colorSpace: Int32,
               minLuminance: Float, maxLuminance: Float) {
    endDolbyVision()
    currentFrame = (pixelBuffer, colorSpace, minLuminance, maxLuminance)
    drawFrame()
  }

  /// Present a VideoToolbox frame carrying Dolby Vision metadata through the
  /// system compositor, with libmpv's OSD/subtitle overlay above it.
  func displayDolbyVision(video: CVPixelBuffer, overlay: CVPixelBuffer?) {
    guard presentationEnabled, isEligibleForPresentation,
      UIApplication.shared.applicationState == .active else { return }
    let view: DolbyVisionPassthroughView
    if let existing = dolbyVisionView {
      view = existing
    } else {
      view = DolbyVisionPassthroughView(frame: bounds)
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.isHidden = true
      view.onFailure = { [weak self] reason in self?.onDolbyVisionFailure?(reason) }
      addSubview(view)
      dolbyVisionView = view
    }
    if view.isHidden {
      // The opaque view covers the EDR layer; stop presenting into it.
      presentationActivity.isActive = false
      pendingFrame.discard()
      currentFrame = nil
      view.frame = bounds
      view.isHidden = false
      NSLog("HDRMetalSurfaceView: presenting native Dolby Vision")
    }
    view.display(video: video, overlay: overlay)
  }

  func endDolbyVision() {
    guard let view = dolbyVisionView, !view.isHidden else { return }
    view.isHidden = true
    view.clear()
  }

  private func drawFrame() {
    // Flutter initially creates the UIKit view with an empty frame. Retain the
    // image until layout/window attachment, including a paused first frame.
    let active = presentationEnabled && isEligibleForPresentation &&
      UIApplication.shared.applicationState == .active
    presentationActivity.isActive = active
    guard active, let frame = currentFrame else { pendingFrame.discard(); return }
    let layer = metalLayer
    // nextDrawable may wait for the compositor. Never hold Flutter's platform
    // thread there; bound the queue to the latest frame while it is waiting.
    if pendingFrame.store(frame, handoff: false) {
      presentationQueue.async { [weak self] in
        guard let self = self, let pending = self.pendingFrame.take() else { return }
        self.present(pending.frame, on: layer)
      }
    }
  }

  private func present(_ frame: Frame, on metalLayer: CAMetalLayer) {
    let started = measuresRenderTime ? CFAbsoluteTimeGetCurrent() : 0
    guard presentationActivity.isActive,
      let surface = CVPixelBufferGetIOSurface(frame.pixel)?.takeUnretainedValue() else { return }
    let width = IOSurfaceGetWidth(surface)
    let height = IOSurfaceGetHeight(surface)
    guard width > 0, height > 0 else { return }

    let pixelFormat: MTLPixelFormat
    switch CVPixelBufferGetPixelFormatType(frame.pixel) {
    case kCVPixelFormatType_ARGB2101010LEPacked: pixelFormat = .bgr10a2Unorm
    case kCVPixelFormatType_64RGBAHalf: pixelFormat = .rgba16Float
    case kCVPixelFormatType_32BGRA: pixelFormat = .bgra8Unorm
    default: return
    }
    // A blit does not scale. Match the actual IOSurface, which can be smaller
    // than the logical video on memory-constrained devices. Core Animation
    // then scales this complete image to the Flutter view's bounds.
    let drawableSize = CGSize(width: width, height: height)
    let colorSpace: Int32 = pixelFormat == .bgra8Unorm ? 0 : frame.colorSpace
    if metalLayer.drawableSize != drawableSize || metalLayer.pixelFormat != pixelFormat ||
      configuredColorSpace != colorSpace || configuredLuminance?.0 != frame.minLuminance ||
      configuredLuminance?.1 != frame.maxLuminance {
      // The dispatch queue has no run loop to flush implicit CA transactions.
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      metalLayer.drawableSize = drawableSize
      metalLayer.pixelFormat = pixelFormat
      configureColorSpace(colorSpace, minLuminance: frame.minLuminance,
        maxLuminance: frame.maxLuminance, on: metalLayer)
      CATransaction.commit()
    }

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: pixelFormat,
      width: width,
      height: height,
      mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    guard let source = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0),
      let drawable = metalLayer.nextDrawable(),
      presentationActivity.isActive,
      drawable.texture.width == width, drawable.texture.height == height,
      let commandBuffer = queue.makeCommandBuffer(),
      let blit = commandBuffer.makeBlitCommandEncoder() else { return }

    blit.copy(
      from: source,
      sourceSlice: 0,
      sourceLevel: 0,
      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
      sourceSize: MTLSize(width: width, height: height, depth: 1),
      to: drawable.texture,
      destinationSlice: 0,
      destinationLevel: 0,
      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
    )
    blit.endEncoding()
    // Retain the CVPixelBuffer itself until the GPU has finished reading it;
    // retaining an MTLTexture alone does not keep the pool from reusing it.
    commandBuffer.addCompletedHandler { [pixelBuffer = frame.pixel] buffer in
      withExtendedLifetime(pixelBuffer) {
        if buffer.status == .error {
          NSLog("HDRMetalSurfaceView: presentation failed: %@", String(describing: buffer.error))
        }
      }
    }
    if measuresRenderTime {
      commandBuffer.addCompletedHandler { [weak self] buffer in
        let elapsed = max(0, buffer.gpuEndTime - buffer.gpuStartTime) * 1000
        DispatchQueue.main.async { [weak self] in
          guard let self = self, self.gpuTimes.count < 3600 else { return }
          self.gpuTimes.append(elapsed)
        }
      }
    }
    commandBuffer.present(drawable)
    commandBuffer.commit()
    if measuresRenderTime {
      let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.submitTimes.count < 3600 else { return }
        self.submitTimes.append(elapsed)
      }
    }
  }

  private func configureColorSpace(_ colorSpace: Int32, minLuminance: Float, maxLuminance: Float,
                                   on metalLayer: CAMetalLayer) {
    guard configuredColorSpace != colorSpace || configuredLuminance?.0 != minLuminance ||
      configuredLuminance?.1 != maxLuminance else { return }
    configuredColorSpace = colorSpace
    configuredLuminance = (minLuminance, maxLuminance)
    if #available(iOS 16.0, *) {
      metalLayer.wantsExtendedDynamicRangeContent = colorSpace != 0
      metalLayer.edrMetadata = nil
    }
    switch colorSpace {
    case Int32(MPV_RENDER_IOSURFACE_COLOR_SPACE_HLG.rawValue):
      if #available(iOS 13.4, *) {
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_HLG)
      }
      if #available(iOS 16.0, *) { metalLayer.edrMetadata = CAEDRMetadata.hlg }
    case Int32(MPV_RENDER_IOSURFACE_COLOR_SPACE_HDR10.rawValue):
      if #available(iOS 13.4, *) {
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)
      }
      if #available(iOS 16.0, *) {
        metalLayer.edrMetadata = CAEDRMetadata.hdr10(
          minLuminance: minLuminance,
          maxLuminance: maxLuminance,
          opticalOutputScale: 10000
        )
      }
    default:
      metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    }
  }
}

/// Flutter draws a `BackdropFilter` above a platform view by inserting a
/// `UIVisualEffectView` sibling over it. Those views accept touches by default,
/// so a finger on a blurred drawer is owned by the effect view. Flutter reuses
/// the effect views by index and removes the trailing ones whenever the number
/// of blurred surfaces drops (controls auto-hiding under an open drawer). UIKit
/// then ends the touch on a detached view whose responder chain no longer
/// reaches the Flutter view controller, the pointer is never released, and
/// every scrollable under it stops settling or bouncing back.
///
/// Leaving the effect views non-interactive routes the touch to Flutter's own
/// intercepting view, which stays mounted for the platform view's lifetime.
enum PlatformViewBackdropTouchRouting {
  private static var patchedClasses = Set<ObjectIdentifier>()

  static func install(for platformView: UIView) {
    guard let container = platformView.superview?.superview else { return }
    let containerClass: AnyClass = type(of: container)
    guard NSStringFromClass(containerClass).hasSuffix("ChildClippingView") else { return }
    for subview in container.subviews { passThrough(subview) }
    guard patchedClasses.insert(ObjectIdentifier(containerClass)).inserted else { return }

    let selector = #selector(UIView.didAddSubview(_:))
    guard let inherited = class_getInstanceMethod(containerClass, selector) else { return }
    typealias Original = @convention(c) (UIView, Selector, UIView) -> Void
    let original = unsafeBitCast(method_getImplementation(inherited), to: Original.self)
    let replacement: @convention(block) (UIView, UIView) -> Void = { container, subview in
      original(container, selector, subview)
      passThrough(subview)
    }
    let implementation = imp_implementationWithBlock(replacement)
    let encoding = method_getTypeEncoding(inherited)
    // The engine class inherits UIView's implementation today. Add an override
    // on that class only; replace in place if a later engine defines its own.
    if !class_addMethod(containerClass, selector, implementation, encoding) {
      method_setImplementation(inherited, implementation)
    }
  }

  private static func passThrough(_ view: UIView) {
    if view is UIVisualEffectView { view.isUserInteractionEnabled = false }
  }
}

/// Flutter's blur intersects its platform-view boundary. Keep that boundary
/// viewport-sized and fit only the video child, including the Dolby Vision
/// surface and its subtitle layer, inside it.
final class HDRMetalViewportView: UIView {
  let surfaceView = HDRMetalSurfaceView(frame: .zero)
  private var videoLayout = IOSNativeVideoLayout()

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    backgroundColor = .black
    addSubview(surfaceView)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func updateLayout(_ arguments: [String: Any]) {
    guard let layout = IOSNativeVideoLayout(arguments: arguments) else { return }
    videoLayout = layout
    let color = layout.fill
    let alpha = CGFloat((color >> 24) & 0xff) / 255
    backgroundColor = UIColor(red: CGFloat((color >> 16) & 0xff) / 255,
      green: CGFloat((color >> 8) & 0xff) / 255, blue: CGFloat(color & 0xff) / 255,
      alpha: alpha)
    isOpaque = alpha == 1
    setNeedsLayout()
    layoutIfNeeded()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let geometry = videoLayout.geometry(in: bounds.size) else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    surfaceView.bounds = geometry.bounds
    surfaceView.center = geometry.center
    surfaceView.transform = geometry.transform
    CATransaction.commit()
    surfaceView.setNeedsLayout()
    surfaceView.layoutIfNeeded()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    // The root is the child of FlutterTouchInterceptingView; the inner video
    // no longer has the ancestry the touch-routing patch expects.
    PlatformViewBackdropTouchRouting.install(for: self)
  }
}

final class HDRMetalVideoPlatformView: NSObject, FlutterPlatformView {
  private let viewportView: HDRMetalViewportView
  var surfaceView: HDRMetalSurfaceView { viewportView.surfaceView }
  let fullscreen: Bool
  var onDispose: (() -> Void)?
  var onLayoutDispose: (() -> Void)?

  init(frame: CGRect, fullscreen: Bool) {
    self.fullscreen = fullscreen
    viewportView = HDRMetalViewportView(frame: frame)
    super.init()
  }

  func view() -> UIView { viewportView }

  func updateLayout(_ arguments: [String: Any]) { viewportView.updateLayout(arguments) }

  deinit {
    if let onDispose = onDispose { DispatchQueue.main.async(execute: onDispose) }
    if let onLayoutDispose = onLayoutDispose { DispatchQueue.main.async(execute: onLayoutDispose) }
  }
}

final class HDRMetalVideoPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let attach: (Int64, HDRMetalVideoPlatformView) -> Void
  private let views = NSMapTable<NSNumber, HDRMetalVideoPlatformView>(
    keyOptions: .strongMemory, valueOptions: .weakMemory)

  init(attach: @escaping (Int64, HDRMetalVideoPlatformView) -> Void) {
    self.attach = attach
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func updateLayout(viewId: Int64, arguments: [String: Any]) {
    // A queued update for a disposed route is a harmless no-op.
    views.object(forKey: NSNumber(value: viewId))?.updateLayout(arguments)
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let dictionary = args as? [String: Any]
    let platformView = HDRMetalVideoPlatformView(frame: frame,
      fullscreen: dictionary?["fullscreen"] as? Bool ?? false)
    let key = NSNumber(value: viewId)
    views.setObject(platformView, forKey: key)
    platformView.onLayoutDispose = { [weak self] in
      guard let self = self, self.views.object(forKey: key) == nil else { return }
      // A later platform view can reuse this ID before asynchronous cleanup.
      self.views.removeObject(forKey: key)
    }
    if let dictionary = dictionary { platformView.updateLayout(dictionary) }
    if let dictionary = dictionary,
      let textureId = dictionary["textureId"] as? NSNumber {
      attach(textureId.int64Value, platformView)
    }
    return platformView
  }
}

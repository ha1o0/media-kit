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
  private var lastPresentationEligibility = false
  private var presentationEnabled = false

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
           "children": child.subviews.map { String(describing: type(of: $0)) } ] as [String: Any]
        }])
      current = view.superview
    }
    return ["ancestors": ancestors, "window": window != nil,
      "hasFrame": currentFrame != nil, "drawableSize": String(describing: metalLayer.drawableSize)]
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
    currentFrame = (pixelBuffer, colorSpace, minLuminance, maxLuminance)
    drawFrame()
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

final class HDRMetalVideoPlatformView: NSObject, FlutterPlatformView {
  let surfaceView: HDRMetalSurfaceView
  let fullscreen: Bool
  var onDispose: (() -> Void)?

  init(frame: CGRect, fullscreen: Bool) {
    self.fullscreen = fullscreen
    surfaceView = HDRMetalSurfaceView(frame: frame)
    super.init()
  }

  func view() -> UIView { surfaceView }

  deinit {
    if let onDispose = onDispose { DispatchQueue.main.async(execute: onDispose) }
  }
}

final class HDRMetalVideoPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let attach: (Int64, HDRMetalVideoPlatformView) -> Void

  init(attach: @escaping (Int64, HDRMetalVideoPlatformView) -> Void) {
    self.attach = attach
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let dictionary = args as? [String: Any]
    let platformView = HDRMetalVideoPlatformView(frame: frame,
      fullscreen: dictionary?["fullscreen"] as? Bool ?? false)
    if let dictionary = dictionary,
      let textureId = dictionary["textureId"] as? NSNumber {
      attach(textureId.int64Value, platformView)
    }
    return platformView
  }
}

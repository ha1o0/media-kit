import AVFoundation
import CoreMedia
import CoreVideo
import IOSurface
import Metal
import QuartzCore
import UIKit

/// Native Dolby Vision presentation. The decoded frame goes to an
/// AVSampleBufferDisplayLayer, so the system compositor applies the per-frame
/// Dolby Vision display mapping (as AVPlayer does). libmpv draws only OSD and
/// subtitles into a transparent sRGB target shown in a layer above it.
///
/// libmpv owns presentation timing: every frame is enqueued for immediate
/// display when libmpv hands it over, exactly like the composited path.
final class DolbyVisionPassthroughView: UIView {
  override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

  private var videoLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
  private let overlayLayer = CAMetalLayer()
  private let device: MTLDevice?
  private let queue: MTLCommandQueue?
  private var formatDescription: CMVideoFormatDescription?
  private var lastVideo: CVPixelBuffer?
  private var overlaySize = CGSize.zero
  private(set) var enqueuedFrames = 0
  private(set) var failures = 0
  var onFailure: ((String) -> Void)?
  private var rejected = false
  private var statusObserver: NSKeyValueObservation?
  // nextDrawable may wait for the compositor: never on the platform thread,
  // and keep at most the latest overlay waiting.
  private let overlayQueue = DispatchQueue(label: "media_kit_video.dovi-overlay", qos: .userInteractive)
  private let pendingOverlay = LatestPictureInPictureFrame<CVPixelBuffer>()

  override init(frame: CGRect) {
    device = MTLCreateSystemDefaultDevice()
    queue = device?.makeCommandQueue()
    super.init(frame: frame)
    isOpaque = true
    backgroundColor = .black
    isUserInteractionEnabled = false
    videoLayer.videoGravity = .resizeAspect
    videoLayer.backgroundColor = UIColor.black.cgColor
    overlayLayer.device = device
    overlayLayer.pixelFormat = .bgra8Unorm
    overlayLayer.framebufferOnly = false
    overlayLayer.isOpaque = false
    overlayLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    overlayLayer.contentsGravity = .resize
    layer.addSublayer(overlayLayer)
    statusObserver = videoLayer.observe(\.status, options: [.new]) { [weak self] layer, _ in
      guard layer.status == .failed else { return }
      DispatchQueue.main.async {
        guard let self = self, !self.isHidden,
          self.videoLayer.status == .failed || self.videoLayer.requiresFlushToResumeDecoding else { return }
        self.reject(String(describing: self.videoLayer.error))
      }
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    layoutOverlay()
  }

  /// libplacebo positions subtitles inside a target with the video's display
  /// aspect; place that target over the aspect-fit video rectangle.
  private func layoutOverlay() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    overlayLayer.frame = overlaySize.width > 0 && overlaySize.height > 0
      ? AVMakeRect(aspectRatio: overlaySize, insideRect: bounds) : bounds
    CATransaction.commit()
  }

  /// Must be called on the main thread.
  @discardableResult
  func display(video: CVPixelBuffer, overlay: CVPixelBuffer?) -> Bool {
    guard !rejected else { return false }
    if videoLayer.status == .failed || videoLayer.requiresFlushToResumeDecoding {
      reject(String(describing: videoLayer.error))
      return false
    }
    // A paused redraw hands the same decoded frame again.
    if video !== lastVideo {
      guard let sample = makeSample(video) else {
        reject("could not create the Dolby Vision sample buffer")
        return false
      }
      videoLayer.enqueue(sample)
      lastVideo = video
      enqueuedFrames += 1
    }
    if let overlay = overlay { schedule(overlay) }
    return true
  }

  private func reject(_ reason: String) {
    guard !rejected else { return }
    rejected = true
    failures += 1
    pendingOverlay.discard()
    videoLayer.flushAndRemoveImage()
    lastVideo = nil
    NSLog("DolbyVisionPassthroughView: falling back to mpv: %@", reason)
    onFailure?(reason)
  }

  private func schedule(_ overlay: CVPixelBuffer) {
    guard let surface = CVPixelBufferGetIOSurface(overlay)?.takeUnretainedValue() else { return }
    let size = CGSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
    if overlaySize != size {
      overlaySize = size
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      overlayLayer.drawableSize = size
      CATransaction.commit()
      layoutOverlay()
    }
    guard pendingOverlay.store(overlay, handoff: false) else { return }
    overlayQueue.async { [weak self] in
      guard let self = self, let pending = self.pendingOverlay.take() else { return }
      self.present(pending.frame)
    }
  }

  /// Drops the retained image, e.g. when the source is no longer Dolby Vision.
  func clear() {
    pendingOverlay.discard()
    videoLayer.flushAndRemoveImage()
    lastVideo = nil
    formatDescription = nil
    rejected = false
  }

  private func makeSample(_ pixel: CVPixelBuffer) -> CMSampleBuffer? {
    if formatDescription == nil ||
      !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: pixel) {
      var description: CMVideoFormatDescription?
      guard CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: pixel,
        formatDescriptionOut: &description) == noErr else { return nil }
      formatDescription = description
    }
    guard let description = formatDescription else { return nil }
    var timing = CMSampleTimingInfo(duration: .invalid,
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    guard CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescription: description,
      sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample = sample else { return nil }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
      CFArrayGetCount(attachments) > 0 {
      let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(dictionary,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
    return sample
  }

  private func present(_ overlay: CVPixelBuffer) {
    guard let device = device, let queue = queue,
      CVPixelBufferGetPixelFormatType(overlay) == kCVPixelFormatType_32BGRA,
      let surface = CVPixelBufferGetIOSurface(overlay)?.takeUnretainedValue() else { return }
    let width = IOSurfaceGetWidth(surface), height = IOSurfaceGetHeight(surface)
    guard width > 0, height > 0 else { return }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = .shaderRead
    guard let source = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0),
      let drawable = overlayLayer.nextDrawable(),
      drawable.texture.width == width, drawable.texture.height == height,
      let commandBuffer = queue.makeCommandBuffer(),
      let blit = commandBuffer.makeBlitCommandEncoder() else { return }
    blit.copy(from: source, sourceSlice: 0, sourceLevel: 0,
      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: width, height: height, depth: 1),
      to: drawable.texture, destinationSlice: 0, destinationLevel: 0,
      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
    blit.endEncoding()
    commandBuffer.addCompletedHandler { [overlay] _ in withExtendedLifetime(overlay) {} }
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  func stats() -> [String: Any] {
    ["enqueued": enqueuedFrames, "failures": failures,
     "status": videoLayer.status.rawValue,
     "error": videoLayer.error.map { String(describing: $0) } ?? NSNull(),
     "rpuBytes": lastVideo.map { DolbyVisionFrame.describe($0)["rpuBytes"] ?? 0 } ?? 0,
     "transfer": lastVideo.map { DolbyVisionFrame.describe($0)["transfer"] ?? "absent" } ?? "absent",
     "overlaySize": String(describing: overlaySize)]
  }
}

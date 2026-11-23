import CoreVideo
import Flutter
import IOSurface
import Metal
import QuartzCore
import UIKit

/// Native EDR presentation surface for libmpv's RGBA16F IOSurface output.
final class HDRMetalSurfaceView: UIView {
  override class var layerClass: AnyClass { CAMetalLayer.self }

  private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private var sourceTexture: MTLTexture?

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
    metalLayer.pixelFormat = .rgba16Float
    metalLayer.framebufferOnly = false
    if #available(iOS 13.4, *) {
      metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)
    }
    if #available(iOS 16.0, *) {
      metalLayer.wantsExtendedDynamicRangeContent = true
      metalLayer.edrMetadata = CAEDRMetadata.hdr10(
        minLuminance: 0.0001,
        maxLuminance: 1000,
        opticalOutputScale: 100
      )
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func display(_ pixelBuffer: CVPixelBuffer, colorSpace: Int32) {
    guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue(),
      let drawable = metalLayer.nextDrawable() else { return }
    let width = IOSurfaceGetWidth(surface)
    let height = IOSurfaceGetHeight(surface)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float,
      width: width,
      height: height,
      mipmapped: false
    )
    descriptor.usage = MTLTextureUsage.shaderRead.union(.shaderWrite)
    guard let source = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0),
      let commandBuffer = queue.makeCommandBuffer(),
      let blit = commandBuffer.makeBlitCommandEncoder() else { return }

    configureColorSpace(colorSpace)
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
    commandBuffer.present(drawable)
    commandBuffer.commit()
    sourceTexture = source
  }

  private func configureColorSpace(_ colorSpace: Int32) {
    switch colorSpace {
    case Int32(MPV_RENDER_IOSURFACE_COLOR_SPACE_HLG.rawValue):
      if #available(iOS 13.4, *) {
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_HLG)
      }
      if #available(iOS 17.0, *) { metalLayer.edrMetadata = nil }
    case Int32(MPV_RENDER_IOSURFACE_COLOR_SPACE_HDR10.rawValue):
      if #available(iOS 13.4, *) {
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)
      }
      if #available(iOS 16.0, *) {
        metalLayer.edrMetadata = CAEDRMetadata.hdr10(
          minLuminance: 0.0001,
          maxLuminance: 1000,
          opticalOutputScale: 100
        )
      }
    default:
      metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
      if #available(iOS 16.0, *) { metalLayer.edrMetadata = nil }
    }
  }
}

final class HDRMetalVideoPlatformView: NSObject, FlutterPlatformView {
  let surfaceView: HDRMetalSurfaceView

  init(frame: CGRect) {
    surfaceView = HDRMetalSurfaceView(frame: frame)
    super.init()
  }

  func view() -> UIView { surfaceView }
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
    let platformView = HDRMetalVideoPlatformView(frame: frame)
    if let dictionary = args as? [String: Any],
      let textureId = dictionary["textureId"] as? NSNumber {
      attach(textureId.int64Value, platformView)
    }
    return platformView
  }
}

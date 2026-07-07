import CoreGraphics

#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public protocol ResizableTextureProtocol: NSObject, FlutterTexture {
  func resize(_ size: CGSize)
  func render(_ size: CGSize)
  func setPostProcessingEffect(_ effect: String, enabled: Bool) -> Bool
}

public extension ResizableTextureProtocol {
  func setPostProcessingEffect(_: String, enabled _: Bool) -> Bool {
    return false
  }
}

import CoreVideo
import Flutter
import Foundation

protocol IOSVideoFrameTexture: ResizableTextureProtocol {
  /// Returns true only when a pixel buffer was rendered and made available.
  func renderVideoFrame(_ size: CGSize, needsDecodedFrame: Bool) -> Bool
}

/// Flutter owns one stable texture ID while the worker swaps mpv renderers.
/// Retain only the last published frame, never the renderer that produced it.
final class InlineVideoTexture: NSObject, FlutterTexture {
  private let lock = NSLock()
  private var frame: CVPixelBuffer?

  func publish(_ frame: CVPixelBuffer) {
    lock.lock()
    defer { lock.unlock() }
    self.frame = frame
  }

  var latestFrame: CVPixelBuffer? {
    lock.lock()
    defer { lock.unlock() }
    return frame
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    latestFrame.map { Unmanaged.passRetained($0) }
  }
}

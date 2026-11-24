import CoreGraphics
import Foundation

/// Geometry of the inner video, independent of the full-size UIKit boundary.
struct IOSNativeVideoLayout {
  var x: CGFloat = 0
  var y: CGFloat = 0
  var width: CGFloat = 1
  var height: CGFloat = 1
  var quarterTurns = 0
  var mirror = false
  var fill: UInt32 = 0xff000000

  init() {}

  init?(arguments: [String: Any]) {
    func number(_ key: String, _ fallback: CGFloat) -> CGFloat {
      (arguments[key] as? NSNumber).map { CGFloat($0.doubleValue) } ?? fallback
    }
    x = number("x", 0)
    y = number("y", 0)
    width = number("width", 1)
    height = number("height", 1)
    let rotation = number("rotation", 0)
    guard [x, y, width, height, rotation].allSatisfy({ $0.isFinite }),
      width > 0, height > 0 else { return nil }
    let normalizedRotation = (rotation.truncatingRemainder(dividingBy: 360) + 360)
      .truncatingRemainder(dividingBy: 360)
    quarterTurns = Int(normalizedRotation / 90)
    mirror = arguments["mirror"] as? Bool ?? false
    fill = (arguments["fill"] as? NSNumber)?.uint32Value ?? 0xff000000
  }

  struct Geometry {
    let bounds: CGRect
    let center: CGPoint
    let transform: CGAffineTransform
  }

  func geometry(in viewport: CGSize) -> Geometry? {
    guard viewport.width.isFinite, viewport.height.isFinite,
      viewport.width > 0, viewport.height > 0 else { return nil }
    let picture = CGRect(x: x * viewport.width, y: y * viewport.height,
      width: width * viewport.width, height: height * viewport.height)
    guard [picture.minX, picture.minY, picture.width, picture.height,
      picture.midX, picture.midY].allSatisfy({ $0.isFinite }) else { return nil }
    let size = quarterTurns.isMultiple(of: 2) ? picture.size
      : CGSize(width: picture.height, height: picture.width)
    return Geometry(bounds: CGRect(origin: .zero, size: size),
      center: CGPoint(x: picture.midX, y: picture.midY),
      transform: CGAffineTransform(rotationAngle: CGFloat(quarterTurns) * .pi / 2)
        .scaledBy(x: mirror ? -1 : 1, y: 1))
  }
}

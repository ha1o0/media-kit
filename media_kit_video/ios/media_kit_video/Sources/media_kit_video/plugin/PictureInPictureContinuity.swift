import Foundation

// Keep rendering inline for a foreground-only PiP round trip. Once the app
// goes inactive with PiP, stay on software until both App and inline video
// are foreground again; delegate and lifecycle callbacks may arrive in either order.
struct PictureInPictureRenderPolicy {
  var appIsActive = true
  var presenting = false

  func usesSoftware(currentlySoftware: Bool, framesArmed: Bool = false) -> Bool {
    if !appIsActive && (presenting || framesArmed) { return true }
    if appIsActive && !presenting { return false }
    return currentlySoftware
  }

  func usesSameDecoder(framesArmed: Bool, supported: Bool, currentlyDraining: Bool) -> Bool {
    !appIsActive && supported && (presenting || framesArmed || currentlyDraining)
  }
}

/// Lifecycle signals must be visible before already queued render callbacks,
/// so a delayed worker cannot submit a new GPU frame after willResignActive.
final class PictureInPictureAppActivity {
  private let lock = NSLock()
  private var active = true

  var isActive: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return active
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      active = newValue
    }
  }
}

struct PictureInPictureFrameHandoff {
  private(set) var needsDecodedFrame = false

  mutating func begin() { needsDecodedFrame = true }
  mutating func didPublishFrame() { needsDecodedFrame = false }

  static func isDecodedFrame(present: Bool, redraw: Bool, repeated: Bool) -> Bool {
    present && !redraw && !repeated
  }
}

enum DecodedPictureInPictureColorPolicy {
  static func accepts(transfer: String?, primaries: String?) -> Bool {
    // Decoder-owned CVPixelBuffers may omit Core Video transfer attachments.
    // Check mpv's stream metadata too, so an 8-bit HDR surface cannot be
    // mistaken for SDR merely because its pixel format is NV12.
    primaries == "bt.709" && ["bt.1886", "srgb", "gamma2.2", "gamma2.4"].contains(transfer ?? "")
  }
}

/// AVKit consumes frames on the main queue. If that queue is delayed during a
/// lifecycle transition, keep the newest frame instead of queuing IOSurfaces.
final class LatestPictureInPictureFrame<Frame> {
  private let lock = NSLock()
  private var pending: Frame?
  private var deliveryScheduled = false
  private var needsImmediateDisplay = false

  /// Returns true only when the caller must schedule a delivery.
  func store(_ frame: Frame, handoff: Bool) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    pending = frame
    needsImmediateDisplay = needsImmediateDisplay || handoff
    if deliveryScheduled { return false }
    deliveryScheduled = true
    return true
  }

  func take() -> (frame: Frame, handoff: Bool)? {
    lock.lock()
    defer { lock.unlock() }
    let delivery = pending.map { (frame: $0, handoff: needsImmediateDisplay) }
    pending = nil
    deliveryScheduled = false
    needsImmediateDisplay = false
    return delivery
  }

  func discard() {
    lock.lock()
    defer { lock.unlock() }
    pending = nil
    needsImmediateDisplay = false
    // A drain already on the main queue still owns this slot.
  }
}

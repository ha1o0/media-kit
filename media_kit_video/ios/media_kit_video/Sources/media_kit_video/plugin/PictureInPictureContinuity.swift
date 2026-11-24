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
  /// What AVKit may be told about a decoder-owned frame.
  enum Kind: Equatable { case sdr, pq, hlg }

  static func accepts(transfer: String?, primaries: String?) -> Bool {
    // Decoder-owned CVPixelBuffers may omit Core Video transfer attachments.
    // Check mpv's stream metadata too, so an 8-bit HDR surface cannot be
    // mistaken for SDR merely because its pixel format is NV12.
    primaries == "bt.709" && ["bt.1886", "srgb", "gamma2.2", "gamma2.4"].contains(transfer ?? "")
  }

  /// A raw HDR sample is only correct when the inline player is itself
  /// presenting HDR (the user did not ask for an SDR mapping) and the decoded
  /// pixels are ordinary BT.2020 PQ/HLG. Dolby Vision profile 5 decodes to
  /// IPT-PQ-C2, which needs the RPU reshaping that only libplacebo applies.
  static func kind(transfer: String?, primaries: String?, matrix: String?,
                   hdrOutputActive: Bool) -> Kind? {
    if accepts(transfer: transfer, primaries: primaries) { return .sdr }
    guard hdrOutputActive, primaries == "bt.2020",
      let matrix = matrix, matrix.hasPrefix("bt.2020") else { return nil }
    switch transfer {
    case "pq", "st2084", "st-2084": return .pq
    case "hlg", "arib-std-b67": return .hlg
    default: return nil
    }
  }
}

/// Core Video color tags for frames handed to AVKit. The compositor reads
/// these, not mpv's metadata, to decide whether a sample is HDR.
enum PictureInPictureColorTags {
  /// `colorSpace` uses libmpv's IOSurface target values: 1 = HDR10, 2 = HLG.
  static func kind(colorSpace: Int32) -> DecodedPictureInPictureColorPolicy.Kind? {
    switch colorSpace {
    case 1: return .pq
    case 2: return .hlg
    default: return nil
    }
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

import Foundation

/// Select the actual display target, never just the source's HDR label.
enum IOSHdrOutputPolicy {
  static func colorSpace(enabled: Bool, potentialHeadroom: Double,
                         hint: String?, transfer: String?, primaries: String?) -> Int32 {
    guard enabled, potentialHeadroom > 1.0, ["auto", "yes"].contains(hint ?? ""),
      primaries == "bt.2020" else { return 0 }
    switch transfer {
    case "pq", "st2084", "st-2084": return 1
    case "hlg", "arib-std-b67": return 2
    default: return 0
    }
  }
}

/// mpv scales to its render target. Target pixels the screen cannot show are
/// rendered, kept in memory and then scaled away again by Core Animation: a
/// 4K source is 8.3 million pixels per frame on a 3 million pixel iPhone.
/// Render at the size that covers the screen in either orientation instead,
/// so no fit mode loses visible detail.
enum IOSRenderTargetPolicy {
  static func size(for video: CGSize, screen: CGSize) -> CGSize {
    let screenLong = max(screen.width, screen.height)
    let screenShort = min(screen.width, screen.height)
    let videoLong = max(video.width, video.height)
    let videoShort = min(video.width, video.height)
    guard screenShort >= 1, videoShort >= 1, screenLong.isFinite else { return video }
    let scale = max(screenLong / videoLong, screenShort / videoShort)
    guard scale < 1 else { return video }
    // Nearest, not down: 1920 * (1792 / 1920) must not become 1791.
    return CGSize(width: max(2, (video.width * scale).rounded()),
                  height: max(2, (video.height * scale).rounded()))
  }
}

/// Candidates arrive in creation order, which is not route visibility order.
enum IOSHdrPresentationPolicy {
  struct Candidate {
    let eligible: Bool
    let fullscreen: Bool
  }

  static func selectedIndex(_ candidates: [Candidate]) -> Int? {
    candidates.indices.last { candidates[$0].eligible && candidates[$0].fullscreen }
      ?? candidates.indices.last { candidates[$0].eligible }
  }
}

/// Standard-message-codec-safe diagnostics (enabled only by the device probe).
enum IOSRenderTiming {
  static func summary(_ values: [Double]) -> [String: Any] {
    let sorted = values.sorted()
    let count = sorted.count
    return ["frames": count,
      "averageMs": count == 0 ? 0.0 : sorted.reduce(0, +) / Double(count),
      "p95Ms": count == 0 ? 0.0 : sorted[min(count - 1, Int(Double(count) * 0.95))],
      "maxMs": count == 0 ? 0.0 : sorted[count - 1]]
  }
}

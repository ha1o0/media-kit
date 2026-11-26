import Foundation

/// Native Dolby Vision is an output choice, not a replacement for mpv's
/// picture processing. Keep the existing compositor whenever it is needed.
enum IOSDolbyVisionOutputPolicy {
  static func composesPictureInPicture(framesArmed: Bool, nativePermitted: Bool,
                                      compositionSupported: Bool,
                                      primary: String?, primaryVisible: String?,
                                      secondary: String?, secondaryVisible: String?) -> Bool {
    func selected(_ track: String?, _ visible: String?) -> Bool {
      guard let track = track, let id = Int(track), id > 0 else { return false }
      return visible != "no"
    }
    return framesArmed && nativePermitted && compositionSupported &&
      (selected(primary, primaryVisible) || selected(secondary, secondaryVisible))
  }

  static func permits(enabled: Bool, systemSupported: Bool, hint: String?,
                      profile: Int?, needsPictureProcessing: Bool, rejected: Bool) -> Bool {
    enabled && systemSupported && ["auto", "yes"].contains(hint ?? "") &&
      [5, 8].contains(profile ?? 0) && !needsPictureProcessing && !rejected
  }

  /// Dolby Vision's base-layer signal compatibility, never a guessed HDR10
  /// fallback for P5. Core Animation expects this value as a string.
  static func compatibilityID(profile: Int?, transfer: String?) -> String? {
    switch (profile, transfer) {
    case (5, _): return "0"
    case (8, "pq"), (8, "st2084"), (8, "st-2084"): return "1"
    case (8, "hlg"), (8, "arib-std-b67"): return "4"
    default: return nil
    }
  }
}

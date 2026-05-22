public class VideoOutputConfiguration {
  public let width: Int64?
  public let height: Int64?
  public let enableHardwareAcceleration: Bool
  public let renderBackend: String?

  init(
    width: Int64?,
    height: Int64?,
    enableHardwareAcceleration: Bool,
    renderBackend: String?
  ) {
    self.width = width
    self.height = height
    self.enableHardwareAcceleration = enableHardwareAcceleration
    self.renderBackend = renderBackend
  }

  public static func fromDict(_ dict: [String: Any])
    -> VideoOutputConfiguration
  {
    let widthStr = dict["width"] as! String
    let heightStr = dict["height"] as! String
    let enableHardwareAcceleration =
      dict["enableHardwareAcceleration"] as! Bool
    let renderBackendStr = dict["renderBackend"] as? String

    let width: Int64? = Int64(widthStr)
    let height: Int64? = Int64(heightStr)
    let renderBackend =
      renderBackendStr == nil || renderBackendStr == "null"
      ? nil
      : renderBackendStr

    return VideoOutputConfiguration(
      width: width,
      height: height,
      enableHardwareAcceleration: enableHardwareAcceleration,
      renderBackend: renderBackend
    )
  }
}

#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public class VideoOutputManager: NSObject {
  private let registry: FlutterTextureRegistry
  private var videoOutputs = [Int64: VideoOutput]()

  init(registry: FlutterTextureRegistry) {
    self.registry = registry
  }

  public func create(
    handle: Int64,
    configuration: VideoOutputConfiguration,
    textureUpdateCallback: @escaping VideoOutput.TextureUpdateCallback
  ) {
    let videoOutput = VideoOutput(
      handle: handle,
      configuration: configuration,
      registry: self.registry,
      textureUpdateCallback: textureUpdateCallback
    )

    self.videoOutputs[handle] = videoOutput
  }

  #if os(iOS)
    public func attachHdrView(textureId: Int64, view: HDRMetalVideoPlatformView) {
      videoOutputs.values.first(where: { $0.matchesTextureId(textureId) })?.attachHdrView(view)
    }
  #endif

  public func setSize(
    handle: Int64,
    width: Int64?,
    height: Int64?
  ) {
    let videoOutput = self.videoOutputs[handle]
    if videoOutput == nil {
      return
    }

    videoOutput!.setSize(
      width: width,
      height: height
    )
  }

  public func setPostProcessingEffect(
    handle: Int64,
    effect: String,
    enabled: Bool
  ) -> Bool {
    let videoOutput = self.videoOutputs[handle]
    if videoOutput == nil {
      return false
    }

    return videoOutput!.setPostProcessingEffect(effect, enabled: enabled)
  }

  #if os(iOS)
    public func copyArtwork(handle: Int64, completion: @escaping (Data?) -> Void) {
      guard let output = videoOutputs[handle] else {
        completion(nil)
        return
      }
      output.copyArtwork(completion: completion)
    }
  #endif

  public func destroy(
    handle: Int64
  ) {
    let videoOutput = self.videoOutputs[handle]
    if videoOutput == nil {
      return
    }

    self.videoOutputs[handle] = nil
  }
}

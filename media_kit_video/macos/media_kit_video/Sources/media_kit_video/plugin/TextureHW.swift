import FlutterMacOS
import OpenGL.GL
import OpenGL.GL3

#if SWIFT_PACKAGE
  import Mpv
#endif

public class TextureHW: NSObject, FlutterTexture, ResizableTextureProtocol {
  public typealias UpdateCallback = () -> Void

  private let handle: OpaquePointer
  private let renderBackend: String?
  private let updateCallback: UpdateCallback
  private let pixelFormat: CGLPixelFormatObj
  private let context: CGLContextObj
  private let textureCache: CVOpenGLTextureCache
  private var renderContext: OpaquePointer?
  private var textureContexts = SwappableObjectManager<TextureGLContext>(
    objects: [],
    skipCheckArgs: true
  )
  private var anime4kEnabled: Bool = false
  private var anime4kProcessor: OpenGLAnime4KProcessor?

  init(
    handle: OpaquePointer,
    renderBackend: String?,
    updateCallback: @escaping UpdateCallback
  ) {
    self.handle = handle
    self.renderBackend = renderBackend
    self.updateCallback = updateCallback
    self.pixelFormat = OpenGLHelpers.createPixelFormat()
    self.context = OpenGLHelpers.createContext(pixelFormat)
    self.textureCache = OpenGLHelpers.createTextureCache(context, pixelFormat)

    super.init()

    self.initMPV()
  }

  deinit {
    disposePixelBuffer()
    disposeMPV()
    CGLSetCurrentContext(context)
    anime4kProcessor = nil
    CGLSetCurrentContext(nil)
    OpenGLHelpers.deleteTextureCache(textureCache)
    OpenGLHelpers.deletePixelFormat(pixelFormat)

    // Deleting the context may cause potential RAM or VRAM memory leaks, as it
    // is used in the `deinit` method of the `TextureGLContext`.
    // Potential fix: use a counter, and delete it only when the counter reaches
    // zero
    OpenGLHelpers.deleteContext(context)
  }

  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let textureContext = textureContexts.current
    if textureContext == nil {
      return nil
    }

    return Unmanaged.passRetained(textureContext!.pixelBuffer)
  }

  private func initMPV() {
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("initMPV")
      CGLSetCurrentContext(nil)
    }

    let api = UnsafeMutableRawPointer(
      mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String
    )
    var procAddress = mpv_opengl_init_params(
      get_proc_address: {
        (ctx, name) in
        return TextureHW.getProcAddress(ctx, name)
      },
      get_proc_address_ctx: nil
    )
    let backendString = renderBackend.map { $0 as NSString }
    let backend = backendString.map {
      UnsafeMutableRawPointer(mutating: $0.utf8String)
    }

    func makeParams(
      _ procAddress: UnsafeMutableRawBufferPointer,
      includeBackend: Bool
    ) -> [mpv_render_param] {
      var params = [
        mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
        mpv_render_param(
          type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
          data: procAddress.baseAddress.map {
            UnsafeMutableRawPointer($0)
          }
        ),
        mpv_render_param(),
      ]

      if includeBackend,
        let renderBackend = renderBackend,
        let backend = backend
      {
        // MPV_RENDER_PARAM_BACKEND was added after media-kit's bundled v0.36
        // headers, but newer bundled libmpv versions understand this ABI value.
        let renderParamBackend = mpv_render_param_type(rawValue: 21)
        NSLog("TextureHW: using mpv render backend \(renderBackend)")
        params.insert(
          mpv_render_param(type: renderParamBackend, data: backend),
          at: 1
        )
      }

      return params
    }

    var params: [mpv_render_param] = withUnsafeMutableBytes(of: &procAddress) {
      procAddress in
      return makeParams(procAddress, includeBackend: renderBackend != nil)
    }

    var status = mpv_render_context_create(&renderContext, handle, &params)
    if status < 0 && renderBackend != nil {
      NSLog("TextureHW: falling back to default mpv render backend")
      params = withUnsafeMutableBytes(of: &procAddress) {
        procAddress in
        return makeParams(procAddress, includeBackend: false)
      }
      status = mpv_render_context_create(&renderContext, handle, &params)
    }
    MPVHelpers.checkError(status)

    mpv_render_context_set_update_callback(
      renderContext,
      { (ctx) in
        let that = unsafeBitCast(ctx, to: TextureHW.self)
        DispatchQueue.main.async {
          that.updateCallback()
        }
      },
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )
  }

  private func disposeMPV() {
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("disposeMPV")
      CGLSetCurrentContext(nil)
    }

    mpv_render_context_set_update_callback(renderContext, nil, nil)
    mpv_render_context_free(renderContext)
  }

  public func resize(_ size: CGSize) {
    if size.width == 0 || size.height == 0 {
      return
    }

    NSLog("TextureGL: resize: \(size.width)x\(size.height)")
    createPixelBuffer(size)
  }

  public func setPostProcessingEffect(_ effect: String, enabled: Bool) -> Bool {
    if effect != "anime4k.restore_cnn_s" {
      return false
    }

    anime4kEnabled = enabled
    if enabled {
      anime4kProcessor?.initFailed = false
    } else {
      CGLSetCurrentContext(context)
      anime4kProcessor = nil
      OpenGLHelpers.checkError("setPostProcessingEffect")
      CGLSetCurrentContext(nil)
    }
    return true
  }

  private func createPixelBuffer(_ size: CGSize) {
    disposePixelBuffer()

    textureContexts.reinit(
      objects: [
        TextureGLContext(
          context: context,
          textureCache: textureCache,
          size: size
        ),
        TextureGLContext(
          context: context,
          textureCache: textureCache,
          size: size
        ),
        TextureGLContext(
          context: context,
          textureCache: textureCache,
          size: size
        ),
      ],
      skipCheckArgs: true
    )
  }

  private func disposePixelBuffer() {
    textureContexts.reinit(objects: [], skipCheckArgs: true)
  }

  public func render(_ size: CGSize) {
    let textureContext = textureContexts.nextAvailable()
    if textureContext == nil {
      return
    }

    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("render")
      CGLSetCurrentContext(nil)
    }

    let outputFrameBuffer = textureContext!.frameBuffer
    var renderFrameBuffer = outputFrameBuffer
    var anime4kReady = false
    if anime4kEnabled {
      if anime4kProcessor == nil {
        anime4kProcessor = OpenGLAnime4KProcessor()
      }
      if let anime4kProcessor = anime4kProcessor,
        !anime4kProcessor.initFailed,
        anime4kProcessor.ensureSize(size)
      {
        renderFrameBuffer = anime4kProcessor.inputFrameBuffer
        anime4kReady = true
      }
    }

    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), renderFrameBuffer)
    defer {
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    var fbo = mpv_opengl_fbo(
      fbo: Int32(renderFrameBuffer),
      w: Int32(size.width),
      h: Int32(size.height),
      internal_format: 0
    )
    let fboPtr = withUnsafeMutablePointer(to: &fbo) { $0 }

    var params: [mpv_render_param] = [
      mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
      mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
    ]
    mpv_render_context_render(renderContext, &params)

    if anime4kReady,
      let anime4kProcessor = anime4kProcessor
    {
      if !anime4kProcessor.process(outputFrameBuffer: outputFrameBuffer) {
        _ = anime4kProcessor.copyInput(to: outputFrameBuffer)
        NSLog("TextureHW: Anime4K pass failed; copied original frame")
        anime4kProcessor.initFailed = true
      }
    }

    glFlush()

    textureContexts.pushAsReady(textureContext!)
  }

  static private func getProcAddress(
    _ ctx: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<Int8>?
  ) -> UnsafeMutableRawPointer? {
    let symbol: CFString = CFStringCreateWithCString(
      kCFAllocatorDefault,
      name,
      kCFStringEncodingASCII
    )
    let indentifier = CFBundleGetBundleWithIdentifier(
      "com.apple.opengl" as CFString
    )
    let addr = CFBundleGetFunctionPointerForName(indentifier, symbol)

    if addr == nil {
      NSLog("Cannot get OpenGL function pointer!")
    }
    return addr
  }
}

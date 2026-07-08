// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright (c) 2026 Predidit.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

import CoreGraphics
import Foundation
import OpenGL.GL
import OpenGL.GL3

public final class OpenGLAnime4KProcessor {
  private let vertices: [GLfloat] = [
    -1.0, -1.0, 0.0, 0.0,
     1.0, -1.0, 1.0, 0.0,
    -1.0,  1.0, 0.0, 1.0,
     1.0,  1.0, 1.0, 1.0,
  ]

  private var width: GLsizei = 0
  private var height: GLsizei = 0
  private var inputTexture: GLuint = 0
  public private(set) var inputFrameBuffer: GLuint = 0
  private var restoreTextures: [GLuint] = [0, 0, 0]
  private var restoreFrameBuffers: [GLuint] = [0, 0, 0]
  private var programs: [GLuint] = [0, 0, 0, 0]
  private var copyProgram: GLuint = 0
  public var initFailed = false
  private var vertexBuffer: GLuint = 0

  deinit {
    deleteFrameTextures()
    deleteShaders()
  }

  public func ensureSize(_ size: CGSize) -> Bool {
    if initFailed {
      return false
    }

    let requiredWidth = max(GLsizei(size.width), 1)
    let requiredHeight = max(GLsizei(size.height), 1)

    if !ensureShaders() {
      initFailed = true
      return false
    }

    if inputTexture != 0 &&
      inputFrameBuffer != 0 &&
      width == requiredWidth &&
      height == requiredHeight
    {
      return true
    }

    deleteFrameTextures()

    guard let input = createTextureAndFrameBuffer(
      width: requiredWidth,
      height: requiredHeight,
      internalFormat: GLint(GL_RGBA),
      format: GLenum(GL_RGBA),
      type: GLenum(GL_UNSIGNED_BYTE)
    ) else {
      initFailed = true
      return false
    }

    inputTexture = input.texture
    inputFrameBuffer = input.frameBuffer

    for index in 0..<restoreTextures.count {
      var restore = createTextureAndFrameBuffer(
        width: requiredWidth,
        height: requiredHeight,
        internalFormat: GLint(GL_RGBA16F),
        format: GLenum(GL_RGBA),
        type: GLenum(GL_HALF_FLOAT)
      )

      if restore == nil {
        restore = createTextureAndFrameBuffer(
          width: requiredWidth,
          height: requiredHeight,
          internalFormat: GLint(GL_RGBA),
          format: GLenum(GL_RGBA),
          type: GLenum(GL_UNSIGNED_BYTE)
        )
      }

      guard let restoreResult = restore else {
        NSLog("OpenGLAnime4KProcessor: restore framebuffer \(index) is incomplete")
        deleteFrameTextures()
        initFailed = true
        return false
      }
      restoreTextures[index] = restoreResult.texture
      restoreFrameBuffers[index] = restoreResult.frameBuffer
    }

    width = requiredWidth
    height = requiredHeight
    return true
  }

  public func process(outputFrameBuffer: GLuint) -> Bool {
    if inputTexture == 0 || inputFrameBuffer == 0 {
      return false
    }

    if !renderPass(
      program: programs[0],
      outputFrameBuffer: restoreFrameBuffers[0],
      sourceTexture: inputTexture
    ) {
      return false
    }
    if !renderPass(
      program: programs[1],
      outputFrameBuffer: restoreFrameBuffers[1],
      sourceTexture: restoreTextures[0]
    ) {
      return false
    }
    if !renderPass(
      program: programs[2],
      outputFrameBuffer: restoreFrameBuffers[2],
      sourceTexture: restoreTextures[1]
    ) {
      return false
    }
    return renderPass(
      program: programs[3],
      outputFrameBuffer: outputFrameBuffer,
      sourceTexture: inputTexture,
      convTexture: restoreTextures[2]
    )
  }

  public func copyInput(to outputFrameBuffer: GLuint) -> Bool {
    if inputTexture == 0 || copyProgram == 0 {
      return false
    }

    return renderPass(
      program: copyProgram,
      outputFrameBuffer: outputFrameBuffer,
      sourceTexture: inputTexture
    )
  }

  private func ensureShaders() -> Bool {
    if initFailed {
      return false
    }
    if copyProgram != 0 && programs.allSatisfy({ $0 != 0 }) {
      return true
    }

    for index in 0..<Anime4KRestoreCNNShaders.restorePasses.count {
      let program = linkProgram(
        vertexSource: Anime4KRestoreCNNShaders.vertex,
        fragmentSource: Anime4KRestoreCNNShaders.restorePasses[index]
      )
      if program == 0 {
        initFailed = true
        return false
      }
      programs[index] = program
    }

    copyProgram = linkProgram(
      vertexSource: Anime4KRestoreCNNShaders.vertex,
      fragmentSource: Anime4KRestoreCNNShaders.copyFragment
    )
    if copyProgram == 0 {
      initFailed = true
      return false
    }

    glGenBuffers(1, &vertexBuffer)
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBuffer)
    vertices.withUnsafeBytes { buffer in
      glBufferData(
        GLenum(GL_ARRAY_BUFFER),
        buffer.count,
        buffer.baseAddress,
        GLenum(GL_STATIC_DRAW)
      )
    }
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
    return true
  }

  private func createTextureAndFrameBuffer(
    width: GLsizei,
    height: GLsizei,
    internalFormat: GLint,
    format: GLenum,
    type: GLenum
  ) -> (texture: GLuint, frameBuffer: GLuint)? {
    var texture: GLuint = 0
    glGenTextures(1, &texture)
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_NEAREST)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_NEAREST)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
    glTexImage2D(
      GLenum(GL_TEXTURE_2D),
      0,
      internalFormat,
      width,
      height,
      0,
      format,
      type,
      nil
    )

    var frameBuffer: GLuint = 0
    glGenFramebuffers(1, &frameBuffer)
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
    glFramebufferTexture2D(
      GLenum(GL_FRAMEBUFFER),
      GLenum(GL_COLOR_ATTACHMENT0),
      GLenum(GL_TEXTURE_2D),
      texture,
      0
    )

    let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    glBindTexture(GLenum(GL_TEXTURE_2D), 0)

    if status == GLenum(GL_FRAMEBUFFER_COMPLETE) {
      return (texture, frameBuffer)
    }

    glDeleteFramebuffers(1, &frameBuffer)
    glDeleteTextures(1, &texture)
    return nil
  }

  private func renderPass(
    program: GLuint,
    outputFrameBuffer: GLuint,
    sourceTexture: GLuint,
    convTexture: GLuint = 0
  ) -> Bool {
    if program == 0 || outputFrameBuffer == 0 || sourceTexture == 0 {
      return false
    }

    var initialError = glGetError()
    while initialError != GL_NO_ERROR {
      initialError = glGetError()
    }

    var oldProgram: GLint = 0
    var oldArrayBuffer: GLint = 0
    var oldVertexArray: GLint = 0
    var oldFrameBuffer: GLint = 0
    var oldActiveTexture: GLint = 0
    var oldViewport: [GLint] = [0, 0, 0, 0]
    let blendEnabled = glIsEnabled(GLenum(GL_BLEND))
    let depthEnabled = glIsEnabled(GLenum(GL_DEPTH_TEST))
    let scissorEnabled = glIsEnabled(GLenum(GL_SCISSOR_TEST))

    glGetIntegerv(GLenum(GL_CURRENT_PROGRAM), &oldProgram)
    glGetIntegerv(GLenum(GL_ARRAY_BUFFER_BINDING), &oldArrayBuffer)
    glGetIntegerv(GLenum(GL_VERTEX_ARRAY_BINDING), &oldVertexArray)
    glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &oldFrameBuffer)
    glGetIntegerv(GLenum(GL_ACTIVE_TEXTURE), &oldActiveTexture)
    oldViewport.withUnsafeMutableBufferPointer { buffer in
      glGetIntegerv(GLenum(GL_VIEWPORT), buffer.baseAddress)
    }

    glDisable(GLenum(GL_BLEND))
    glDisable(GLenum(GL_DEPTH_TEST))
    glDisable(GLenum(GL_SCISSOR_TEST))
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), outputFrameBuffer)
    glViewport(0, 0, width, height)
    glUseProgram(program)

    var localVAO: GLuint = 0
    glGenVertexArrays(1, &localVAO)
    glBindVertexArray(localVAO)

    glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBuffer)
    glEnableVertexAttribArray(0)
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(
      0,
      2,
      GLenum(GL_FLOAT),
      GLboolean(GL_FALSE),
      GLsizei(4 * MemoryLayout<GLfloat>.size),
      UnsafeRawPointer(bitPattern: 0)
    )
    glVertexAttribPointer(
      1,
      2,
      GLenum(GL_FLOAT),
      GLboolean(GL_FALSE),
      GLsizei(4 * MemoryLayout<GLfloat>.size),
      UnsafeRawPointer(bitPattern: 2 * MemoryLayout<GLfloat>.size)
    )

    let texSizeLocation = glGetUniformLocation(program, "tex_size")
    if texSizeLocation >= 0 {
      glUniform2f(texSizeLocation, GLfloat(width), GLfloat(height))
    }

    glActiveTexture(GLenum(GL_TEXTURE0))
    glBindTexture(GLenum(GL_TEXTURE_2D), sourceTexture)
    let sourceLocation = glGetUniformLocation(program, "source_texture")
    if sourceLocation >= 0 {
      glUniform1i(sourceLocation, 0)
    }

    if convTexture != 0 {
      glActiveTexture(GLenum(GL_TEXTURE1))
      glBindTexture(GLenum(GL_TEXTURE_2D), convTexture)
      let convLocation = glGetUniformLocation(program, "conv_texture")
      if convLocation >= 0 {
        glUniform1i(convLocation, 1)
      }
    }

    glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)

    glDisableVertexAttribArray(0)
    glDisableVertexAttribArray(1)
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)
    glBindVertexArray(0)
    glDeleteVertexArrays(1, &localVAO)

    glActiveTexture(GLenum(GL_TEXTURE1))
    glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    glActiveTexture(GLenum(GL_TEXTURE0))
    glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    glUseProgram(GLuint(oldProgram))
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), GLuint(oldArrayBuffer))
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(oldFrameBuffer))
    glBindVertexArray(GLuint(oldVertexArray))
    glViewport(oldViewport[0], oldViewport[1], oldViewport[2], oldViewport[3])
    if blendEnabled == GL_TRUE {
      glEnable(GLenum(GL_BLEND))
    }
    if depthEnabled == GL_TRUE {
      glEnable(GLenum(GL_DEPTH_TEST))
    }
    if scissorEnabled == GL_TRUE {
      glEnable(GLenum(GL_SCISSOR_TEST))
    }
    glActiveTexture(GLenum(oldActiveTexture))

    let err = glGetError()
    if err != GL_NO_ERROR {
      NSLog("OpenGLAnime4KProcessor: renderPass failed with OpenGL error: 0x\(String(err, radix: 16))")
      return false
    }
    return true
  }

  private func linkProgram(vertexSource: String, fragmentSource: String) -> GLuint {
    let vertexShader = compileShader(type: GLenum(GL_VERTEX_SHADER), source: vertexSource)
    if vertexShader == 0 {
      return 0
    }

    let fragmentShader = compileShader(type: GLenum(GL_FRAGMENT_SHADER), source: fragmentSource)
    if fragmentShader == 0 {
      glDeleteShader(vertexShader)
      return 0
    }

    let program = glCreateProgram()
    glAttachShader(program, vertexShader)
    glAttachShader(program, fragmentShader)
    glBindAttribLocation(program, 0, "a_position")
    glBindAttribLocation(program, 1, "a_uv")
    glLinkProgram(program)
    glDeleteShader(vertexShader)
    glDeleteShader(fragmentShader)

    var linked: GLint = 0
    glGetProgramiv(program, GLenum(GL_LINK_STATUS), &linked)
    if linked == GL_TRUE {
      return program
    }

    logProgramError(program)
    glDeleteProgram(program)
    return 0
  }

  private func compileShader(type: GLenum, source: String) -> GLuint {
    let shader = glCreateShader(type)
    source.withCString { pointer in
      var sourcePointer: UnsafePointer<GLchar>? = pointer
      glShaderSource(shader, 1, &sourcePointer, nil)
      glCompileShader(shader)
    }

    var compiled: GLint = 0
    glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &compiled)
    if compiled == GL_TRUE {
      return shader
    }

    logShaderError(shader)
    glDeleteShader(shader)
    return 0
  }

  private func logShaderError(_ shader: GLuint) {
    var logLength: GLint = 0
    glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &logLength)
    var log = [GLchar](repeating: 0, count: max(Int(logLength), 1))
    log.withUnsafeMutableBufferPointer { buffer in
      glGetShaderInfoLog(shader, GLsizei(buffer.count), nil, buffer.baseAddress)
    }
    let message = log.withUnsafeBufferPointer { buffer in
      String(cString: buffer.baseAddress!)
    }
    NSLog("OpenGLAnime4KProcessor: shader compile failed: \(message)")
  }

  private func logProgramError(_ program: GLuint) {
    var logLength: GLint = 0
    glGetProgramiv(program, GLenum(GL_INFO_LOG_LENGTH), &logLength)
    var log = [GLchar](repeating: 0, count: max(Int(logLength), 1))
    log.withUnsafeMutableBufferPointer { buffer in
      glGetProgramInfoLog(program, GLsizei(buffer.count), nil, buffer.baseAddress)
    }
    let message = log.withUnsafeBufferPointer { buffer in
      String(cString: buffer.baseAddress!)
    }
    NSLog("OpenGLAnime4KProcessor: program link failed: \(message)")
  }

  private func deleteFrameTextures() {
    if inputTexture != 0 {
      glDeleteTextures(1, &inputTexture)
      inputTexture = 0
    }
    if inputFrameBuffer != 0 {
      glDeleteFramebuffers(1, &inputFrameBuffer)
      inputFrameBuffer = 0
    }
    for index in 0..<restoreTextures.count {
      if restoreTextures[index] != 0 {
        var texture = restoreTextures[index]
        glDeleteTextures(1, &texture)
        restoreTextures[index] = 0
      }
      if restoreFrameBuffers[index] != 0 {
        var frameBuffer = restoreFrameBuffers[index]
        glDeleteFramebuffers(1, &frameBuffer)
        restoreFrameBuffers[index] = 0
      }
    }
    width = 0
    height = 0
  }

  private func deleteShaders() {
    for index in 0..<programs.count {
      if programs[index] != 0 {
        glDeleteProgram(programs[index])
        programs[index] = 0
      }
    }
    if copyProgram != 0 {
      glDeleteProgram(copyProgram)
      copyProgram = 0
    }
    if vertexBuffer != 0 {
      glDeleteBuffers(1, &vertexBuffer)
      vertexBuffer = 0
    }
  }
}

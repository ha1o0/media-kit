// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright (c) 2026 Predidit.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "include/media_kit_video/opengl_anime4k_processor.h"

#include <array>
#include <cstring>
#include <iostream>
#include <vector>

#include "opengl_anime4k_restore_s_shaders.h"

#ifndef GL_HALF_FLOAT_OES
#define GL_HALF_FLOAT_OES 0x8D61
#endif

namespace {

constexpr GLfloat kVertices[] = {
    -1.0f, -1.0f, 0.0f, 0.0f,
     1.0f, -1.0f, 1.0f, 0.0f,
    -1.0f,  1.0f, 0.0f, 1.0f,
     1.0f,  1.0f, 1.0f, 1.0f,
};

bool HasExtension(const char* extensions, const char* extension) {
  return extensions != nullptr && std::strstr(extensions, extension) != nullptr;
}

bool SupportsES3() {
  const char* version =
      reinterpret_cast<const char*>(glGetString(GL_VERSION));
  return version != nullptr && std::strstr(version, "OpenGL ES 3") != nullptr;
}

GLuint CompileShader(GLenum type, const char* source) {
  GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, nullptr);
  glCompileShader(shader);

  GLint compiled = GL_FALSE;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
  if (compiled == GL_TRUE) {
    return shader;
  }

  GLint log_length = 0;
  glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &log_length);
  std::vector<char> log(log_length > 1 ? log_length : 1);
  glGetShaderInfoLog(shader, static_cast<GLsizei>(log.size()), nullptr,
                     log.data());
  std::cout << "media_kit: OpenGLAnime4KProcessor: shader compile failed: "
            << log.data() << std::endl;
  glDeleteShader(shader);
  return 0;
}

GLuint LinkProgram(const char* vertex_source, const char* fragment_source) {
  GLuint vertex_shader = CompileShader(GL_VERTEX_SHADER, vertex_source);
  if (vertex_shader == 0) {
    return 0;
  }

  GLuint fragment_shader = CompileShader(GL_FRAGMENT_SHADER, fragment_source);
  if (fragment_shader == 0) {
    glDeleteShader(vertex_shader);
    return 0;
  }

  GLuint program = glCreateProgram();
  glAttachShader(program, vertex_shader);
  glAttachShader(program, fragment_shader);
  glBindAttribLocation(program, 0, "a_position");
  glBindAttribLocation(program, 1, "a_uv");
  glLinkProgram(program);

  glDeleteShader(vertex_shader);
  glDeleteShader(fragment_shader);

  GLint linked = GL_FALSE;
  glGetProgramiv(program, GL_LINK_STATUS, &linked);
  if (linked == GL_TRUE) {
    return program;
  }

  GLint log_length = 0;
  glGetProgramiv(program, GL_INFO_LOG_LENGTH, &log_length);
  std::vector<char> log(log_length > 1 ? log_length : 1);
  glGetProgramInfoLog(program, static_cast<GLsizei>(log.size()), nullptr,
                      log.data());
  std::cout << "media_kit: OpenGLAnime4KProcessor: program link failed: "
            << log.data() << std::endl;
  glDeleteProgram(program);
  return 0;
}

}  // namespace

struct _OpenGLAnime4KProcessor {
  guint32 width = 0;
  guint32 height = 0;
  guint32 input_texture = 0;
  guint32 input_fbo = 0;
  std::array<guint32, 3> restore_textures = {0, 0, 0};
  std::array<guint32, 3> restore_fbos = {0, 0, 0};
  std::array<guint32, 4> programs = {0, 0, 0, 0};
  guint32 copy_program = 0;
  guint32 vertex_buffer = 0;
  bool shaders_ready = false;
  bool half_float_unavailable_reported = false;
};

OpenGLAnime4KProcessor* opengl_anime4k_processor_new() {
  return new OpenGLAnime4KProcessor();
}

void opengl_anime4k_processor_free(OpenGLAnime4KProcessor* self) {
  if (self == nullptr) {
    return;
  }

  if (self->input_texture != 0) {
    glDeleteTextures(1, &self->input_texture);
  }
  if (self->input_fbo != 0) {
    glDeleteFramebuffers(1, &self->input_fbo);
  }
  for (auto& texture : self->restore_textures) {
    if (texture != 0) {
      glDeleteTextures(1, &texture);
    }
  }
  for (auto& fbo : self->restore_fbos) {
    if (fbo != 0) {
      glDeleteFramebuffers(1, &fbo);
    }
  }
  for (auto& program : self->programs) {
    if (program != 0) {
      glDeleteProgram(program);
    }
  }
  if (self->copy_program != 0) {
    glDeleteProgram(self->copy_program);
  }
  if (self->vertex_buffer != 0) {
    glDeleteBuffers(1, &self->vertex_buffer);
  }

  delete self;
}

static gboolean ensure_shaders(OpenGLAnime4KProcessor* self) {
  if (self->shaders_ready) {
    return TRUE;
  }

  for (size_t i = 0; i < self->programs.size(); ++i) {
    self->programs[i] = LinkProgram(
        anime4k_restore_s_gl::kVertexShader,
        anime4k_restore_s_gl::kPassFragmentShaders[i]);
    if (self->programs[i] == 0) {
      return FALSE;
    }
  }

  self->copy_program = LinkProgram(anime4k_restore_s_gl::kVertexShader,
                                   anime4k_restore_s_gl::kCopyFragmentShader);
  if (self->copy_program == 0) {
    return FALSE;
  }

  glGenBuffers(1, &self->vertex_buffer);
  glBindBuffer(GL_ARRAY_BUFFER, self->vertex_buffer);
  glBufferData(GL_ARRAY_BUFFER, sizeof(kVertices), kVertices, GL_STATIC_DRAW);
  glBindBuffer(GL_ARRAY_BUFFER, 0);

  self->shaders_ready = true;
  return TRUE;
}

static gboolean create_texture_and_fbo(guint32 width,
                                       guint32 height,
                                       GLenum internal_format,
                                       GLenum format,
                                       GLenum type,
                                       guint32* texture,
                                       guint32* fbo) {
  glGenTextures(1, texture);
  glBindTexture(GL_TEXTURE_2D, *texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D, 0, internal_format, width, height, 0, format,
               type, nullptr);

  glGenFramebuffers(1, fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, *fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         *texture, 0);
  const GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glBindTexture(GL_TEXTURE_2D, 0);

  if (status == GL_FRAMEBUFFER_COMPLETE) {
    return TRUE;
  }

  glDeleteFramebuffers(1, fbo);
  glDeleteTextures(1, texture);
  *fbo = 0;
  *texture = 0;
  return FALSE;
}

static void delete_frame_textures(OpenGLAnime4KProcessor* self) {
  if (self->input_texture != 0) {
    glDeleteTextures(1, &self->input_texture);
    self->input_texture = 0;
  }
  if (self->input_fbo != 0) {
    glDeleteFramebuffers(1, &self->input_fbo);
    self->input_fbo = 0;
  }
  for (auto& texture : self->restore_textures) {
    if (texture != 0) {
      glDeleteTextures(1, &texture);
      texture = 0;
    }
  }
  for (auto& fbo : self->restore_fbos) {
    if (fbo != 0) {
      glDeleteFramebuffers(1, &fbo);
      fbo = 0;
    }
  }
  self->width = 0;
  self->height = 0;
}

gboolean opengl_anime4k_processor_ensure_size(OpenGLAnime4KProcessor* self,
                                               guint32 width,
                                               guint32 height) {
  if (self == nullptr) {
    return FALSE;
  }

  width = width > 0 ? width : 1;
  height = height > 0 ? height : 1;

  if (!ensure_shaders(self)) {
    return FALSE;
  }

  if (self->input_texture != 0 && self->input_fbo != 0 &&
      self->width == width && self->height == height) {
    return TRUE;
  }

  delete_frame_textures(self);

  if (!create_texture_and_fbo(width, height, GL_RGBA, GL_RGBA,
                              GL_UNSIGNED_BYTE, &self->input_texture,
                              &self->input_fbo)) {
    return FALSE;
  }

  GLenum half_internal_format = GL_RGBA;
  GLenum half_type = GL_HALF_FLOAT_OES;
  const char* extensions =
      reinterpret_cast<const char*>(glGetString(GL_EXTENSIONS));
  const bool supports_es3 = SupportsES3();
  if (supports_es3) {
#ifdef GL_RGBA16F
    half_internal_format = GL_RGBA16F;
#endif
#ifdef GL_HALF_FLOAT
    half_type = GL_HALF_FLOAT;
#endif
  } else if (!HasExtension(extensions, "GL_OES_texture_half_float") ||
             !HasExtension(extensions, "GL_EXT_color_buffer_half_float")) {
    if (!self->half_float_unavailable_reported) {
      std::cout << "media_kit: OpenGLAnime4KProcessor: half-float render "
                   "targets are unavailable."
                << std::endl;
      self->half_float_unavailable_reported = true;
    }
    delete_frame_textures(self);
    return FALSE;
  }

  for (size_t i = 0; i < self->restore_textures.size(); ++i) {
    if (!create_texture_and_fbo(width, height, half_internal_format, GL_RGBA,
                                half_type, &self->restore_textures[i],
                                &self->restore_fbos[i])) {
      std::cout << "media_kit: OpenGLAnime4KProcessor: restore framebuffer "
                << i << " is incomplete." << std::endl;
      delete_frame_textures(self);
      return FALSE;
    }
  }

  self->width = width;
  self->height = height;
  return TRUE;
}

guint32 opengl_anime4k_processor_get_input_fbo(
    OpenGLAnime4KProcessor* self) {
  return self != nullptr ? self->input_fbo : 0;
}

static gboolean render_pass(OpenGLAnime4KProcessor* self,
                            guint32 program,
                            guint32 output_fbo,
                            guint32 source_texture,
                            guint32 conv_texture) {
  if (program == 0 || output_fbo == 0 || source_texture == 0) {
    return FALSE;
  }

  GLint old_program = 0;
  GLint old_array_buffer = 0;
  GLint old_framebuffer = 0;
  GLint old_active_texture = 0;
  GLint old_viewport[4] = {0, 0, 0, 0};
  GLboolean blend_enabled = glIsEnabled(GL_BLEND);
  GLboolean depth_enabled = glIsEnabled(GL_DEPTH_TEST);
  GLboolean scissor_enabled = glIsEnabled(GL_SCISSOR_TEST);

  glGetIntegerv(GL_CURRENT_PROGRAM, &old_program);
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &old_array_buffer);
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &old_framebuffer);
  glGetIntegerv(GL_ACTIVE_TEXTURE, &old_active_texture);
  glGetIntegerv(GL_VIEWPORT, old_viewport);

  glDisable(GL_BLEND);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_SCISSOR_TEST);
  glBindFramebuffer(GL_FRAMEBUFFER, output_fbo);
  glViewport(0, 0, self->width, self->height);
  glUseProgram(program);
  glBindBuffer(GL_ARRAY_BUFFER, self->vertex_buffer);

  glEnableVertexAttribArray(0);
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat),
                        reinterpret_cast<const void*>(0));
  glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat),
                        reinterpret_cast<const void*>(2 * sizeof(GLfloat)));

  GLint size_location = glGetUniformLocation(program, "tex_size");
  if (size_location >= 0) {
    glUniform2f(size_location, static_cast<GLfloat>(self->width),
                static_cast<GLfloat>(self->height));
  }

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, source_texture);
  GLint source_location = glGetUniformLocation(program, "source_texture");
  if (source_location >= 0) {
    glUniform1i(source_location, 0);
  }

  if (conv_texture != 0) {
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, conv_texture);
    GLint conv_location = glGetUniformLocation(program, "conv_texture");
    if (conv_location >= 0) {
      glUniform1i(conv_location, 1);
    }
  }

  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

  glDisableVertexAttribArray(0);
  glDisableVertexAttribArray(1);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, 0);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, 0);
  glUseProgram(old_program);
  glBindBuffer(GL_ARRAY_BUFFER, old_array_buffer);
  glBindFramebuffer(GL_FRAMEBUFFER, old_framebuffer);
  glViewport(old_viewport[0], old_viewport[1], old_viewport[2],
             old_viewport[3]);
  if (blend_enabled) {
    glEnable(GL_BLEND);
  }
  if (depth_enabled) {
    glEnable(GL_DEPTH_TEST);
  }
  if (scissor_enabled) {
    glEnable(GL_SCISSOR_TEST);
  }
  glActiveTexture(old_active_texture);

  return glGetError() == GL_NO_ERROR;
}

gboolean opengl_anime4k_processor_process(OpenGLAnime4KProcessor* self,
                                           guint32 output_fbo) {
  if (self == nullptr || self->input_texture == 0 || self->input_fbo == 0) {
    return FALSE;
  }

  if (!render_pass(self, self->programs[0], self->restore_fbos[0],
                   self->input_texture, 0)) {
    return FALSE;
  }
  if (!render_pass(self, self->programs[1], self->restore_fbos[1],
                   self->restore_textures[0], 0)) {
    return FALSE;
  }
  if (!render_pass(self, self->programs[2], self->restore_fbos[2],
                   self->restore_textures[1], 0)) {
    return FALSE;
  }
  return render_pass(self, self->programs[3], output_fbo, self->input_texture,
                     self->restore_textures[2]);
}

gboolean opengl_anime4k_processor_copy_input_to_fbo(
    OpenGLAnime4KProcessor* self,
    guint32 output_fbo) {
  if (self == nullptr || self->copy_program == 0 || self->input_texture == 0) {
    return FALSE;
  }
  return render_pass(self, self->copy_program, output_fbo, self->input_texture,
                     0);
}

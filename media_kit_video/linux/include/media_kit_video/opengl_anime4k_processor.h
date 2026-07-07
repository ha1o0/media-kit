// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright (c) 2026 Predidit.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#ifndef OPENGL_ANIME4K_PROCESSOR_H_
#define OPENGL_ANIME4K_PROCESSOR_H_

#include <flutter_linux/flutter_linux.h>
#include <epoxy/gl.h>

typedef struct _OpenGLAnime4KProcessor OpenGLAnime4KProcessor;

OpenGLAnime4KProcessor* opengl_anime4k_processor_new();

void opengl_anime4k_processor_free(OpenGLAnime4KProcessor* self);

gboolean opengl_anime4k_processor_ensure_size(OpenGLAnime4KProcessor* self,
                                               guint32 width,
                                               guint32 height);

guint32 opengl_anime4k_processor_get_input_fbo(
    OpenGLAnime4KProcessor* self);

gboolean opengl_anime4k_processor_process(OpenGLAnime4KProcessor* self,
                                           guint32 output_fbo);

gboolean opengl_anime4k_processor_copy_input_to_fbo(
    OpenGLAnime4KProcessor* self,
    guint32 output_fbo);

#endif  // OPENGL_ANIME4K_PROCESSOR_H_

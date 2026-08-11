// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "video_output.h"

#include <algorithm>

#include "video_output_mode.h"

// Limit the frame size to 1080p in software rendering.
// This is for performance reasons & to avoid allocating too much memory.
#define SW_RENDERING_MAX_WIDTH 1920
#define SW_RENDERING_MAX_HEIGHT 1080
#define SW_RENDERING_PIXEL_BUFFER_SIZE \
  (SW_RENDERING_MAX_WIDTH) * (SW_RENDERING_MAX_HEIGHT) * (4)

VideoOutput::VideoOutput(int64_t handle,
                         VideoOutputConfiguration configuration,
                         flutter::PluginRegistrarWindows* registrar,
                         ThreadPool* thread_pool_ref)
    : handle_(reinterpret_cast<mpv_handle*>(handle)),
      width_(configuration.width),
      height_(configuration.height),
      configuration_(configuration),
      registrar_(registrar),
      thread_pool_ref_(thread_pool_ref) {
  // The constructor must be invoked through the thread pool, because libmpv
  // render context creation can conflict with existing |Render| or |Resize|
  // calls from another |VideoOutput| instance.
  auto future = thread_pool_ref_->Post([&]() {
    mpv_set_option_string(handle_, "video-sync", "audio");
    mpv_set_option_string(handle_, "video-timing-offset", "0");
    // First try to initialize native D3D11 hardware rendering, use S/W API as
    // fallback.
    auto is_hardware_acceleration_enabled = false;
    // Attempt to use H/W rendering.
    if (configuration.enable_hardware_acceleration) {
      try {
        IDXGIAdapter* flutter_adapter = nullptr;
        if (auto* view = registrar_->GetView()) {
          flutter_adapter = view->GetGraphicsAdapter();
        }

        d3d11_renderer_ = std::make_unique<D3D11Renderer>(
            static_cast<int32_t>(width_.value_or(1)),
            static_cast<int32_t>(height_.value_or(1)), flutter_adapter,
            media_kit_video::GetVideoOutputMode());
        d3d11_renderer_->SetFrameAvailableCallback(
            [this]() { MarkCurrentTextureFrameAvailable(); });
        mpv_d3d11_init_params d3d11_init_params{
            d3d11_renderer_->device(),
        };
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_API_TYPE, MPV_RENDER_API_TYPE_D3D11},
            {MPV_RENDER_PARAM_D3D11_INIT_PARAMS, &d3d11_init_params},
            {MPV_RENDER_PARAM_INVALID, nullptr},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        if (!configuration_.render_backend.empty()) {
          params[2].type = MPV_RENDER_PARAM_BACKEND;
          params[2].data =
              const_cast<char*>(configuration_.render_backend.c_str());
          std::cout << "media_kit: VideoOutput: Using mpv render backend "
                    << configuration_.render_backend << "." << std::endl;
        }
        // Create render context.
        auto status =
            mpv_render_context_create(&render_context_, handle_, params);
        const auto allow_backend_fallback =
            !configuration_.render_backend.empty() &&
            configuration_.render_backend != "gpu-next";
        if (status != 0 && allow_backend_fallback) {
          params[2].type = MPV_RENDER_PARAM_INVALID;
          params[2].data = nullptr;
          std::cout << "media_kit: VideoOutput: Falling back to default mpv "
                       "render backend."
                    << std::endl;
          status =
              mpv_render_context_create(&render_context_, handle_, params);
        } else if (status != 0 && !configuration_.render_backend.empty()) {
          std::cout << "media_kit: VideoOutput: Requested mpv render backend "
                    << configuration_.render_backend
                    << " failed with status " << status
                    << "; not falling back to default gpu backend."
                    << std::endl;
        }
        if (status == 0) {
          mpv_render_context_set_update_callback(
              render_context_,
              [](void* context) {
                // Notify Flutter that a new frame is available. The actual
                // rendering will take place in the |Render| method, which will
                // be called by Flutter on the render thread.
                auto that = reinterpret_cast<VideoOutput*>(context);
                that->NotifyRender();
              },
              reinterpret_cast<void*>(this));
          Resize(width_.value_or(1), height_.value_or(1));
          // Set flag to true, indicating that H/W rendering is supported.
          is_hardware_acceleration_enabled = true;
          std::cout << "media_kit: VideoOutput: Using native D3D11 H/W "
                       "rendering."
                    << std::endl;
        } else {
          std::cout << "media_kit: VideoOutput: Failed to create D3D11 mpv "
                       "render context."
                    << std::endl;
          d3d11_renderer_.reset(nullptr);
        }
      } catch (const std::exception& e) {
        std::cout << "media_kit: VideoOutput: Failed to initialize D3D11: "
                  << e.what() << ", falling back to S/W." << std::endl;
        d3d11_renderer_.reset(nullptr);
      } catch (...) {
        std::cout << "media_kit: VideoOutput: Failed to initialize D3D11, "
                     "falling back to S/W."
                  << std::endl;
        d3d11_renderer_.reset(nullptr);
      }
    }
    if (!is_hardware_acceleration_enabled) {
      std::cout << "media_kit: VideoOutput: Using S/W rendering." << std::endl;
      // Allocate a "large enough" buffer ahead of time.
      pixel_buffer_ =
          std::make_unique<uint8_t[]>(SW_RENDERING_PIXEL_BUFFER_SIZE);
      Resize(width_.value_or(1), height_.value_or(1));
      mpv_render_param params[] = {
          {MPV_RENDER_PARAM_API_TYPE, MPV_RENDER_API_TYPE_SW},
          {MPV_RENDER_PARAM_INVALID, nullptr},
      };
      if (mpv_render_context_create(&render_context_, handle_, params) == 0) {
        mpv_render_context_set_update_callback(
            render_context_,
            [](void* context) {
              // Notify Flutter that a new frame is available. The actual
              // rendering will take place in the |Render| method, which will be
              // called by Flutter on the render thread.
              auto that = reinterpret_cast<VideoOutput*>(context);
              that->NotifyRender();
            },
            reinterpret_cast<void*>(this));
      }
    }
  });
  future.wait();
}

VideoOutput::~VideoOutput() {
  destroyed_ = true;
  auto promise = std::promise<void>();
  int64_t texture_id = 0;
  {
    std::lock_guard<std::mutex> lock(frame_notification_mutex_);
    texture_id = texture_id_;
    texture_id_ = 0;
  }
  if (texture_id) {
    registrar_->texture_registrar()->UnregisterTexture(
        texture_id, [&, texture_id]() {
          // Add one more task into the thread pool queue & exit the destructor
          // only when it gets executed. This will ensure that all the tasks
          // posted to the thread pool i.e. render or resize before this are
          // executed (and won't reference the dead object anymore), most
          // notably |CheckAndResize| & |Render|.
          auto future = thread_pool_ref_->Post([&, id = texture_id]() {
            std::cout << "media_kit: VideoOutput: Free Texture: " << id
                      << std::endl;
            std::cout << "VideoOutput::~VideoOutput: "
                      << reinterpret_cast<int64_t>(handle_) << std::endl;
            std::lock_guard<std::mutex> lock(textures_mutex_);
            texture_variants_.clear();
            // H/W
            textures_.clear();
            // S/W
            pixel_buffer_textures_.clear();
            d3d11_renderer_.reset(nullptr);
            promise.set_value();
          });
        });
  } else {
    promise.set_value();
  }

  promise.get_future().wait();

  if (render_context_) {
    thread_pool_ref_->Post([render_context = render_context_]() {
      mpv_render_context_free(render_context);
    });
  }
}

void VideoOutput::NotifyRender() {
  if (destroyed_.load(std::memory_order_acquire)) {
    return;
  }

  render_requested_.store(true, std::memory_order_release);
  if (render_task_pending_.exchange(true, std::memory_order_acq_rel)) {
    return;
  }

  try {
    thread_pool_ref_->Post([this]() {
      render_requested_.store(false, std::memory_order_release);
      if (!destroyed_.load(std::memory_order_acquire)) {
        // Resize and render on the same worker task. This keeps the render
        // state ordered while preventing a 4K60 stream from building an
        // unbounded queue of stale frame jobs.
        CheckAndResize();
        Render();
      }

      render_task_pending_.store(false, std::memory_order_release);
      if (render_requested_.exchange(false, std::memory_order_acq_rel) &&
          !destroyed_.load(std::memory_order_acquire)) {
        NotifyRender();
      }
    });
  } catch (...) {
    render_task_pending_.store(false, std::memory_order_release);
  }
}

void VideoOutput::Render() {
  if (texture_id_) {
    bool frame_available = false;
    // H/W
    if (d3d11_renderer_ != nullptr) {
      auto render_lock = d3d11_renderer_->AcquireRenderLock();
      mpv_d3d11_fbo fbo{
          d3d11_renderer_->render_target(),
          d3d11_renderer_->width(),
          d3d11_renderer_->height(),
      };
      if (fbo.tex != nullptr) {
        mpv_render_param params[]{
            {MPV_RENDER_PARAM_D3D11_FBO, &fbo},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        mpv_render_context_render(render_context_, params);
        frame_available = d3d11_renderer_->ProducerCommit();
      } else if (d3d11_renderer_->ShouldSkipRendering()) {
        int skip_rendering = 1;
        mpv_render_param params[]{
            {MPV_RENDER_PARAM_SKIP_RENDERING, &skip_rendering},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        mpv_render_context_render(render_context_, params);
        frame_available = d3d11_renderer_->ProducerCommit();
      }
    }
    // S/W
    if (pixel_buffer_ != nullptr) {
      int32_t size[]{
          static_cast<int32_t>(pixel_buffer_textures_.at(texture_id_)->width),
          static_cast<int32_t>(pixel_buffer_textures_.at(texture_id_)->height),
      };
      auto pitch = 4 * size[0];
      mpv_render_param params[]{
          {MPV_RENDER_PARAM_SW_SIZE, size},
          {MPV_RENDER_PARAM_SW_FORMAT, "rgb0"},
          {MPV_RENDER_PARAM_SW_STRIDE, &pitch},
          {MPV_RENDER_PARAM_SW_POINTER, pixel_buffer_.get()},
          {MPV_RENDER_PARAM_INVALID, nullptr},
      };
      mpv_render_context_render(render_context_, params);
      frame_available = true;
    }
    if (!frame_available) return;
    MarkCurrentTextureFrameAvailable();
  }
}

void VideoOutput::MarkCurrentTextureFrameAvailable() {
  std::lock_guard<std::mutex> lock(frame_notification_mutex_);
  if (destroyed_.load(std::memory_order_acquire) || !texture_id_) return;

  try {
    registrar_->texture_registrar()->MarkTextureFrameAvailable(texture_id_);
  } catch (...) {
    // The texture can be unregistered while an asynchronous mailbox fence is
    // completing. Treat the notification as obsolete in that case.
  }
}

void VideoOutput::SetTextureUpdateCallback(
    std::function<void(int64_t, int64_t, int64_t)> callback) {
  texture_update_callback_ = callback;
  texture_update_callback_(texture_id_, GetVideoWidth(), GetVideoHeight());
}

void VideoOutput::SetSize(std::optional<int64_t> width,
                          std::optional<int64_t> height) {
  thread_pool_ref_->Post([&, width, height]() {
    if (width.has_value()) {
      // H/W
      if (d3d11_renderer_ != nullptr) {
        width_ = width.value();
      }
      // S/W
      if (pixel_buffer_ != nullptr) {
        // Limit width if software rendering is being used.
        width_ = std::clamp(width.value(), static_cast<int64_t>(0),
                            static_cast<int64_t>(SW_RENDERING_MAX_WIDTH));
      }
    } else {
      width_ = std::nullopt;
    }
    if (height.has_value()) {
      // H/W
      if (d3d11_renderer_ != nullptr) {
        height_ = height.value();
      }
      // S/W
      if (pixel_buffer_ != nullptr) {
        // Limit width if software rendering is being used.
        height_ = std::clamp(height.value(), static_cast<int64_t>(0),
                             static_cast<int64_t>(SW_RENDERING_MAX_HEIGHT));
      }
    } else {
      height_ = std::nullopt;
    }
  });
}

void VideoOutput::SetAnime4KEnabled(bool enabled) {
  thread_pool_ref_->Post([&, enabled]() {
    if (d3d11_renderer_ != nullptr) {
      d3d11_renderer_->SetAnime4KEnabled(enabled);
    }
  });
}

void VideoOutput::SetGPUThreadPriority(int priority) {
  thread_pool_ref_->Post([this, priority]() {
    if (d3d11_renderer_ != nullptr) {
      d3d11_renderer_->SetGPUThreadPriority(priority);
    }
  });
}

void VideoOutput::CheckAndResize() {
  // Check if a new texture with different dimensions is needed.
  auto required_width = GetVideoWidth(), required_height = GetVideoHeight();
  if (required_width < 1 || required_height < 1) {
    // Invalid.
    return;
  }
  int64_t current_width = -1, current_height = -1;
  if (d3d11_renderer_ != nullptr) {
    current_width = d3d11_renderer_->width();
    current_height = d3d11_renderer_->height();
  }
  if (pixel_buffer_ != nullptr) {
    current_width = pixel_buffer_textures_.at(texture_id_)->width;
    current_height = pixel_buffer_textures_.at(texture_id_)->height;
  }
  // Currently rendered video output dimensions.
  // Either H/W or S/W rendered.
  assert(current_width > 0);
  assert(current_height > 0);
  if (required_width == current_width && required_height == current_height) {
    // No creation of new texture required.
    return;
  }
  Resize(required_width, required_height);
}

void VideoOutput::Resize(int64_t required_width, int64_t required_height) {
  std::cout << required_width << " " << required_height << std::endl;
  // Unregister previously registered texture & delete underlying objects.
  int64_t old_texture_id = 0;
  {
    std::lock_guard<std::mutex> lock(frame_notification_mutex_);
    old_texture_id = texture_id_;
    texture_id_ = 0;
  }
  if (old_texture_id) {
    const int64_t id = old_texture_id;
    const bool wait_for_unregister = d3d11_renderer_ != nullptr;
    auto unregister_completed =
        wait_for_unregister ? std::make_shared<std::promise<void>>() : nullptr;
    std::future<void> unregister_future;
    if (unregister_completed) {
      unregister_future = unregister_completed->get_future();
    }
    registrar_->texture_registrar()->UnregisterTexture(
        id, [this, id, unregister_completed]() {
          if (id) {
            std::cout << "media_kit: VideoOutput: Free Texture: " << id
                      << std::endl;
            std::lock_guard<std::mutex> lock(textures_mutex_);
            if (!destroyed_) {
              texture_variants_.erase(id);
              textures_.erase(id);
              pixel_buffer_textures_.erase(id);
            }
          }
          if (unregister_completed) {
            unregister_completed->set_value();
          }
        });
    if (unregister_completed) {
      unregister_future.wait();
    }
  }
  // H/W
  if (d3d11_renderer_ != nullptr) {
    d3d11_renderer_->SetSize(static_cast<int32_t>(required_width),
                             static_cast<int32_t>(required_height));
    auto texture = std::make_unique<GpuSurfaceTextureState>();
    auto* texture_state = texture.get();
    auto& descriptor = texture->descriptor;
    texture->renderer = d3d11_renderer_.get();
    descriptor.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    descriptor.handle = d3d11_renderer_->ReadHandleSnapshot();
    descriptor.width = descriptor.visible_width = d3d11_renderer_->width();
    descriptor.height = descriptor.visible_height = d3d11_renderer_->height();
    if (d3d11_renderer_->UsesNonBlockingMailbox()) {
      descriptor.release_context = texture_state;
      descriptor.release_callback = [](void* context) {
        auto* state = static_cast<GpuSurfaceTextureState*>(context);
        if (state && state->renderer && state->acquired_handle) {
          state->renderer->ConsumerHandleOpened(state->acquired_handle);
        }
      };
    } else {
      descriptor.release_context = nullptr;
      descriptor.release_callback = nullptr;
    }
    descriptor.format = kFlutterDesktopPixelFormatBGRA8888;
    auto texture_variant =
        std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
            kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
            [this, texture_state](auto, auto) {
              std::lock_guard<std::mutex> lock(textures_mutex_);
              if (destroyed_ || !texture_state->renderer) {
                return (FlutterDesktopGpuSurfaceDescriptor*)nullptr;
              }
              const auto handle = texture_state->renderer->ConsumerAcquire();
              if (!handle) {
                return (FlutterDesktopGpuSurfaceDescriptor*)nullptr;
              }
              texture_state->acquired_handle = handle;
              texture_state->descriptor.handle = handle;
              return &texture_state->descriptor;
            }));
    // Register new texture.
    const int64_t texture_id =
        registrar_->texture_registrar()->RegisterTexture(texture_variant.get());
    std::cout << "media_kit: VideoOutput: Create Texture: " << texture_id
              << std::endl;
    {
      std::lock_guard<std::mutex> lock(textures_mutex_);
      textures_.emplace(std::make_pair(texture_id, std::move(texture)));
      texture_variants_.emplace(
          std::make_pair(texture_id, std::move(texture_variant)));
    }
    {
      std::lock_guard<std::mutex> lock(frame_notification_mutex_);
      texture_id_ = texture_id;
    }
    // Notify public texture update callback.
    texture_update_callback_(texture_id, required_width, required_height);
  }
  // S/W
  if (pixel_buffer_ != nullptr) {
    auto pixel_buffer_texture = std::make_unique<FlutterDesktopPixelBuffer>();
    pixel_buffer_texture->buffer = pixel_buffer_.get();
    pixel_buffer_texture->width = required_width;
    pixel_buffer_texture->height = required_height;
    pixel_buffer_texture->release_context = nullptr;
    pixel_buffer_texture->release_callback = [](void*) {};
    auto texture_variant = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture([&](auto, auto) {
          std::lock_guard<std::mutex> lock(textures_mutex_);
          if (texture_id_) {
            return pixel_buffer_textures_.at(texture_id_).get();
          } else {
            return (FlutterDesktopPixelBuffer*)nullptr;
          }
        }));
    // Register new texture.
    const int64_t texture_id =
        registrar_->texture_registrar()->RegisterTexture(texture_variant.get());
    std::cout << "media_kit: VideoOutput: Create Texture: " << texture_id
              << std::endl;
    {
      std::lock_guard<std::mutex> lock(textures_mutex_);
      pixel_buffer_textures_.emplace(
          std::make_pair(texture_id, std::move(pixel_buffer_texture)));
      texture_variants_.emplace(
          std::make_pair(texture_id, std::move(texture_variant)));
    }
    {
      std::lock_guard<std::mutex> lock(frame_notification_mutex_);
      texture_id_ = texture_id;
    }
    // Notify public texture update callback.
    texture_update_callback_(texture_id, required_width, required_height);
  }
}

int64_t VideoOutput::GetVideoWidth() {
  // Fixed width.
  if (width_) {
    return width_.value();
  }
  // Video resolution dependent width.
  int64_t width = 0;
  int64_t height = 0;

  mpv_node params;
  mpv_get_property(handle_, "video-out-params", MPV_FORMAT_NODE, &params);

  int64_t dw = 0, dh = 0, rotate = 0;
  if (params.format == MPV_FORMAT_NODE_MAP) {
    for (int32_t i = 0; i < params.u.list->num; i++) {
      char* key = params.u.list->keys[i];
      auto value = params.u.list->values[i];
      if (value.format == MPV_FORMAT_INT64) {
        if (strcmp(key, "dw") == 0) {
          dw = value.u.int64;
        }
        if (strcmp(key, "dh") == 0) {
          dh = value.u.int64;
        }
        if (strcmp(key, "rotate") == 0) {
          rotate = value.u.int64;
        }
      }
    }
    mpv_free_node_contents(&params);
  }

  width = rotate == 0 || rotate == 180 ? dw : dh;
  height = rotate == 0 || rotate == 180 ? dh : dw;

  if (pixel_buffer_ != nullptr) {
    // Make sure |width| & |height| fit between |SW_RENDERING_MAX_WIDTH| &
    // |SW_RENDERING_MAX_HEIGHT| while maintaining aspect-ratio.
    if (width >= SW_RENDERING_MAX_WIDTH) {
      return SW_RENDERING_MAX_WIDTH;
    }
    if (height >= SW_RENDERING_MAX_HEIGHT) {
      return width / height * SW_RENDERING_MAX_HEIGHT;
    }
  }

  return width;
}

int64_t VideoOutput::GetVideoHeight() {
  // Fixed height.
  if (height_) {
    return height_.value();
  }
  // Video resolution dependent height.
  int64_t width = 0;
  int64_t height = 0;

  mpv_node params;
  mpv_get_property(handle_, "video-out-params", MPV_FORMAT_NODE, &params);

  int64_t dw = 0, dh = 0, rotate = 0;
  if (params.format == MPV_FORMAT_NODE_MAP) {
    for (int32_t i = 0; i < params.u.list->num; i++) {
      char* key = params.u.list->keys[i];
      auto value = params.u.list->values[i];
      if (value.format == MPV_FORMAT_INT64) {
        if (strcmp(key, "dw") == 0) {
          dw = value.u.int64;
        }
        if (strcmp(key, "dh") == 0) {
          dh = value.u.int64;
        }
        if (strcmp(key, "rotate") == 0) {
          rotate = value.u.int64;
        }
      }
    }
    mpv_free_node_contents(&params);
  }

  width = rotate == 0 || rotate == 180 ? dw : dh;
  height = rotate == 0 || rotate == 180 ? dh : dw;

  if (pixel_buffer_ != NULL) {
    // Make sure |width| & |height| fit between |SW_RENDERING_MAX_WIDTH| &
    // |SW_RENDERING_MAX_HEIGHT| while maintaining aspect-ratio.
    if (height >= SW_RENDERING_MAX_HEIGHT) {
      return SW_RENDERING_MAX_HEIGHT;
    }
    if (width >= SW_RENDERING_MAX_WIDTH) {
      return height / width * SW_RENDERING_MAX_WIDTH;
    }
  }

  return height;
}

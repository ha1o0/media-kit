// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "video_output_manager.h"

#include <algorithm>

#include "gpu_thread_priority.h"
#include "video_output_mode.h"

VideoOutputManager::VideoOutputManager(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

void VideoOutputManager::Create(
    int64_t handle,
    VideoOutputConfiguration configuration,
    std::function<void(int64_t, int64_t, int64_t)> texture_update_callback) {
  std::thread([=]() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (video_outputs_.find(handle) == video_outputs_.end()) {
      auto instance = std::make_unique<VideoOutput>(
          handle, configuration, registrar_, thread_pool_.get());
      instance->SetTextureUpdateCallback(texture_update_callback);
      video_outputs_.insert(std::make_pair(handle, std::move(instance)));
    }
  }).detach();
}

void VideoOutputManager::SetSize(int64_t handle,
                                 std::optional<int64_t> width,
                                 std::optional<int64_t> height) {
  std::thread([=]() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (video_outputs_.find(handle) != video_outputs_.end()) {
      video_outputs_[handle]->SetSize(width, height);
    }
  }).detach();
}

void VideoOutputManager::SetAnime4KEnabled(int64_t handle, bool enabled) {
  std::thread([=]() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (video_outputs_.find(handle) != video_outputs_.end()) {
      video_outputs_[handle]->SetAnime4KEnabled(enabled);
    }
  }).detach();
}

void VideoOutputManager::SetGPUThreadPriority(int priority) {
  const auto normalized =
      media_kit_video::NormalizeGpuThreadPriority(priority);
  media_kit_video::g_gpu_thread_priority.store(normalized);
  std::thread([this, normalized]() {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& entry : video_outputs_) {
      entry.second->SetGPUThreadPriority(normalized);
    }
  }).detach();
}

void VideoOutputManager::SetVideoOutputMode(int mode) {
  const auto normalized = media_kit_video::NormalizeVideoOutputMode(mode);
  media_kit_video::g_video_output_mode.store(static_cast<int>(normalized));
}

bool VideoOutputManager::TryGetPerformanceSnapshots(
    std::vector<VideoOutputPerformanceSnapshot>* snapshots) {
  if (!snapshots) return false;
  std::unique_lock<std::mutex> lock(mutex_, std::try_to_lock);
  if (!lock.owns_lock()) return false;
  snapshots->clear();
  snapshots->reserve(video_outputs_.size());
  std::vector<std::pair<int64_t, VideoOutput*>> ordered_outputs;
  ordered_outputs.reserve(video_outputs_.size());
  for (const auto& entry : video_outputs_) {
    ordered_outputs.emplace_back(entry.first, entry.second.get());
  }
  std::sort(ordered_outputs.begin(), ordered_outputs.end(),
            [](const auto& left, const auto& right) {
              return left.first < right.first;
            });
  for (const auto& entry : ordered_outputs) {
    snapshots->emplace_back(entry.second->GetPerformanceSnapshot());
  }
  return true;
}

void VideoOutputManager::Dispose(int64_t handle) {
  std::thread([=]() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (video_outputs_.find(handle) != video_outputs_.end()) {
      video_outputs_.erase(handle);
    }
  }).detach();
}

VideoOutputManager::~VideoOutputManager() {
  std::lock_guard<std::mutex> lock(mutex_);
  // |VideoOutput| destructor will do the relevant cleanup.
  video_outputs_.clear();
  // This destructor is only called when the plugin is being destroyed i.e. the
  // application is being closed. So, doesn't really matter on the other hand.
}

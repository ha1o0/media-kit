// This file is a part of media_kit.

#ifndef PERFORMANCE_METRICS_H_
#define PERFORMANCE_METRICS_H_

#include <Windows.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>

namespace media_kit_video {

// Counters are intentionally process-wide. A Bota playback normally has one
// visible output, while the aggregate also remains useful when a preview and
// a player exist at the same time.
class PerformanceMetrics final {
 public:
  struct Snapshot {
    bool enabled = false;
    uint64_t enabled_elapsed_ms = 0;
    int output_mode = -1;
    int active_outputs = 0;
    bool hardware_acceleration = false;
    bool anime4k_enabled = false;
    int64_t texture_width = 0;
    int64_t texture_height = 0;
    int64_t window_width = 0;
    int64_t window_height = 0;
    int display_dpi = 0;
    int display_refresh_rate = 0;
    std::string render_backend;
    std::string gpu_adapter;
    int gpu_priority_requested = 0;
    int gpu_priority_applied = 0;
    long gpu_priority_hresult = 0;

    uint64_t render_requests = 0;
    uint64_t render_request_coalesced = 0;
    uint64_t render_tasks = 0;
    uint64_t render_queue_wait_total_us = 0;
    uint64_t render_queue_wait_max_us = 0;
    uint64_t mpv_render_calls = 0;
    uint64_t skip_rendering_calls = 0;
    uint64_t mpv_render_total_us = 0;
    uint64_t mpv_render_max_us = 0;
    uint64_t mpv_render_buckets[7] = {};
    uint64_t producer_commits = 0;
    uint64_t producer_commit_failures = 0;
    uint64_t frame_available_marks = 0;
    uint64_t frame_available_failures = 0;
    uint64_t frame_available_total_us = 0;
    uint64_t frame_available_max_us = 0;
    uint64_t flutter_texture_callbacks = 0;
    uint64_t flutter_texture_callback_total_us = 0;
    uint64_t flutter_texture_callback_max_us = 0;
    uint64_t consumer_acquire_calls = 0;
    uint64_t consumer_acquire_total_us = 0;
    uint64_t consumer_acquire_max_us = 0;
    uint64_t texture_callback_no_handle = 0;
    uint64_t texture_handle_changes = 0;
    uint64_t texture_registrations = 0;
    uint64_t texture_resizes = 0;
    uint64_t texture_unregisters = 0;
    uint64_t flushes = 0;
    uint64_t blocking_fence_waits = 0;
    uint64_t blocking_wait_total_us = 0;
    uint64_t blocking_wait_max_us = 0;
    uint64_t nonblocking_fence_polls = 0;
    uint64_t nonblocking_fence_incomplete = 0;
    uint64_t publishes = 0;
    uint64_t pending_slots_current = 0;
    uint64_t pending_slots_max = 0;
    uint64_t mailbox_full = 0;
    uint64_t fixed_handle_copies = 0;
    uint64_t render_target_misses = 0;
  };

  static PerformanceMetrics& Instance() {
    static PerformanceMetrics metrics;
    return metrics;
  }

  bool enabled() const { return enabled_.load(std::memory_order_relaxed); }

  void SetEnabled(bool enabled) {
    if (enabled) {
      ResetCounters();
      enabled_since_tick_.store(::GetTickCount64(), std::memory_order_relaxed);
      enabled_.store(true, std::memory_order_release);
    } else {
      enabled_.store(false, std::memory_order_release);
    }
  }

  void SetOutputInfo(int mode,
                     bool hardware_acceleration,
                     int64_t width,
                     int64_t height,
                     bool anime4k_enabled,
                     const std::string& render_backend) {
    output_mode_.store(mode, std::memory_order_relaxed);
    hardware_acceleration_.store(hardware_acceleration,
                                 std::memory_order_relaxed);
    texture_width_.store(width, std::memory_order_relaxed);
    texture_height_.store(height, std::memory_order_relaxed);
    anime4k_enabled_.store(anime4k_enabled, std::memory_order_relaxed);
    std::lock_guard<std::mutex> lock(metadata_mutex_);
    render_backend_ = render_backend;
  }

  void SetAnime4KEnabled(bool enabled) {
    anime4k_enabled_.store(enabled, std::memory_order_relaxed);
  }

  void SetActiveOutputs(int count) {
    active_outputs_.store(count < 0 ? 0 : count, std::memory_order_relaxed);
  }

  void IncrementActiveOutputs() {
    active_outputs_.fetch_add(1, std::memory_order_relaxed);
  }

  void DecrementActiveOutputs() {
    auto current = active_outputs_.load(std::memory_order_relaxed);
    while (current > 0 &&
           !active_outputs_.compare_exchange_weak(
               current, current - 1, std::memory_order_relaxed)) {
    }
  }

  void SetDisplayInfo(int64_t width,
                      int64_t height,
                      int dpi,
                      int refresh_rate) {
    window_width_.store(width, std::memory_order_relaxed);
    window_height_.store(height, std::memory_order_relaxed);
    display_dpi_.store(dpi, std::memory_order_relaxed);
    display_refresh_rate_.store(refresh_rate, std::memory_order_relaxed);
  }

  void SetGpuAdapter(const std::string& adapter) {
    std::lock_guard<std::mutex> lock(metadata_mutex_);
    gpu_adapter_ = adapter;
  }

  void SetGpuPriorityResult(int requested, int applied, long hresult) {
    gpu_priority_requested_.store(requested, std::memory_order_relaxed);
    gpu_priority_applied_.store(applied, std::memory_order_relaxed);
    gpu_priority_hresult_.store(hresult, std::memory_order_relaxed);
  }

  void AddRenderRequest() { Add(render_requests_); }
  void AddRenderRequestCoalesced() { Add(render_request_coalesced_); }
  void AddRenderTask() { Add(render_tasks_); }
  void AddMpvRenderCall() { Add(mpv_render_calls_); }
  void AddSkipRendering() { Add(skip_rendering_calls_); }
  void AddProducerCommit() { Add(producer_commits_); }
  void AddProducerCommitFailure() { Add(producer_commit_failures_); }
  void AddFrameAvailableMark() { Add(frame_available_marks_); }
  void AddFrameAvailableFailure() { Add(frame_available_failures_); }
  void AddFlutterTextureCallback() { Add(flutter_texture_callbacks_); }
  void AddTextureCallbackNoHandle() { Add(texture_callback_no_handle_); }
  void AddTextureHandleChange() { Add(texture_handle_changes_); }
  void AddTextureRegistration() { Add(texture_registrations_); }
  void AddTextureResize() { Add(texture_resizes_); }
  void AddTextureUnregister() { Add(texture_unregisters_); }
  void AddFlush() { Add(flushes_); }
  void AddBlockingFenceWait() { Add(blocking_fence_waits_); }
  void AddNonBlockingFencePoll() { Add(nonblocking_fence_polls_); }
  void AddNonBlockingFenceIncomplete() { Add(nonblocking_fence_incomplete_); }
  void AddPublish() { Add(publishes_); }
  void AddMailboxFull() { Add(mailbox_full_); }
  void AddFixedHandleCopy() { Add(fixed_handle_copies_); }
  void AddRenderTargetMiss() { Add(render_target_misses_); }

  void ObserveRenderQueueWait(uint64_t elapsed_us) {
    Add(render_queue_wait_total_us_, elapsed_us);
    ObserveMax(render_queue_wait_max_us_, elapsed_us);
  }

  void ObserveFrameAvailableDuration(uint64_t elapsed_us) {
    Add(frame_available_total_us_, elapsed_us);
    ObserveMax(frame_available_max_us_, elapsed_us);
  }

  void ObserveFlutterTextureCallbackDuration(uint64_t elapsed_us) {
    Add(flutter_texture_callback_total_us_, elapsed_us);
    ObserveMax(flutter_texture_callback_max_us_, elapsed_us);
  }

  void ObserveConsumerAcquireDuration(uint64_t elapsed_us) {
    Add(consumer_acquire_calls_);
    Add(consumer_acquire_total_us_, elapsed_us);
    ObserveMax(consumer_acquire_max_us_, elapsed_us);
  }

  void ObserveMpvRenderDuration(uint64_t elapsed_us) {
    Add(mpv_render_total_us_, elapsed_us);
    ObserveMax(mpv_render_max_us_, elapsed_us);
    const int bucket = elapsed_us < 1000   ? 0
                       : elapsed_us < 2000 ? 1
                       : elapsed_us < 4000 ? 2
                       : elapsed_us < 8000 ? 3
                       : elapsed_us < 16000 ? 4
                       : elapsed_us < 33000 ? 5
                                             : 6;
    Add(mpv_render_buckets_[bucket]);
  }

  void ObserveBlockingWaitDuration(uint64_t elapsed_us) {
    Add(blocking_wait_total_us_, elapsed_us);
    ObserveMax(blocking_wait_max_us_, elapsed_us);
  }

  void SetPendingSlots(uint64_t current) {
    if (!enabled()) return;
    pending_slots_current_.store(current, std::memory_order_relaxed);
    ObserveMax(pending_slots_max_, current);
  }

  Snapshot GetSnapshot() const {
    Snapshot result;
    result.enabled = enabled();
    const auto enabled_since =
        enabled_since_tick_.load(std::memory_order_relaxed);
    result.enabled_elapsed_ms =
        enabled_since == 0 ? 0 : ::GetTickCount64() - enabled_since;
    result.output_mode = output_mode_.load(std::memory_order_relaxed);
    result.active_outputs = active_outputs_.load(std::memory_order_relaxed);
    result.hardware_acceleration =
        hardware_acceleration_.load(std::memory_order_relaxed);
    result.anime4k_enabled = anime4k_enabled_.load(std::memory_order_relaxed);
    result.texture_width = texture_width_.load(std::memory_order_relaxed);
    result.texture_height = texture_height_.load(std::memory_order_relaxed);
    result.window_width = window_width_.load(std::memory_order_relaxed);
    result.window_height = window_height_.load(std::memory_order_relaxed);
    result.display_dpi = display_dpi_.load(std::memory_order_relaxed);
    result.display_refresh_rate =
        display_refresh_rate_.load(std::memory_order_relaxed);
    result.gpu_priority_requested =
        gpu_priority_requested_.load(std::memory_order_relaxed);
    result.gpu_priority_applied =
        gpu_priority_applied_.load(std::memory_order_relaxed);
    result.gpu_priority_hresult =
        gpu_priority_hresult_.load(std::memory_order_relaxed);
    {
      std::lock_guard<std::mutex> lock(metadata_mutex_);
      result.render_backend = render_backend_;
      result.gpu_adapter = gpu_adapter_;
    }

#define PERFORMANCE_METRICS_COPY(field) \
  result.field = field##_.load(std::memory_order_relaxed)
    PERFORMANCE_METRICS_COPY(render_requests);
    PERFORMANCE_METRICS_COPY(render_request_coalesced);
    PERFORMANCE_METRICS_COPY(render_tasks);
    PERFORMANCE_METRICS_COPY(render_queue_wait_total_us);
    PERFORMANCE_METRICS_COPY(render_queue_wait_max_us);
    PERFORMANCE_METRICS_COPY(mpv_render_calls);
    PERFORMANCE_METRICS_COPY(skip_rendering_calls);
    PERFORMANCE_METRICS_COPY(mpv_render_total_us);
    PERFORMANCE_METRICS_COPY(mpv_render_max_us);
    PERFORMANCE_METRICS_COPY(producer_commits);
    PERFORMANCE_METRICS_COPY(producer_commit_failures);
    PERFORMANCE_METRICS_COPY(frame_available_marks);
    PERFORMANCE_METRICS_COPY(frame_available_failures);
    PERFORMANCE_METRICS_COPY(frame_available_total_us);
    PERFORMANCE_METRICS_COPY(frame_available_max_us);
    PERFORMANCE_METRICS_COPY(flutter_texture_callbacks);
    PERFORMANCE_METRICS_COPY(flutter_texture_callback_total_us);
    PERFORMANCE_METRICS_COPY(flutter_texture_callback_max_us);
    PERFORMANCE_METRICS_COPY(consumer_acquire_calls);
    PERFORMANCE_METRICS_COPY(consumer_acquire_total_us);
    PERFORMANCE_METRICS_COPY(consumer_acquire_max_us);
    PERFORMANCE_METRICS_COPY(texture_callback_no_handle);
    PERFORMANCE_METRICS_COPY(texture_handle_changes);
    PERFORMANCE_METRICS_COPY(texture_registrations);
    PERFORMANCE_METRICS_COPY(texture_resizes);
    PERFORMANCE_METRICS_COPY(texture_unregisters);
    PERFORMANCE_METRICS_COPY(flushes);
    PERFORMANCE_METRICS_COPY(blocking_fence_waits);
    PERFORMANCE_METRICS_COPY(blocking_wait_total_us);
    PERFORMANCE_METRICS_COPY(blocking_wait_max_us);
    PERFORMANCE_METRICS_COPY(nonblocking_fence_polls);
    PERFORMANCE_METRICS_COPY(nonblocking_fence_incomplete);
    PERFORMANCE_METRICS_COPY(publishes);
    PERFORMANCE_METRICS_COPY(pending_slots_current);
    PERFORMANCE_METRICS_COPY(pending_slots_max);
    PERFORMANCE_METRICS_COPY(mailbox_full);
    PERFORMANCE_METRICS_COPY(fixed_handle_copies);
    PERFORMANCE_METRICS_COPY(render_target_misses);
#undef PERFORMANCE_METRICS_COPY
    for (int i = 0; i < 7; ++i) {
      result.mpv_render_buckets[i] =
          mpv_render_buckets_[i].load(std::memory_order_relaxed);
    }
    return result;
  }

 private:
  PerformanceMetrics() = default;

  template <typename T>
  void Add(std::atomic<T>& counter, T amount = 1) {
    if (!enabled()) return;
    counter.fetch_add(amount, std::memory_order_relaxed);
  }

  template <typename T>
  void ObserveMax(std::atomic<T>& target, T value) {
    if (!enabled()) return;
    auto current = target.load(std::memory_order_relaxed);
    while (current < value &&
           !target.compare_exchange_weak(current, value,
                                         std::memory_order_relaxed)) {
    }
  }

  void ResetCounters() {
#define PERFORMANCE_METRICS_RESET(field) \
  field##_.store(0, std::memory_order_relaxed)
    PERFORMANCE_METRICS_RESET(render_requests);
    PERFORMANCE_METRICS_RESET(render_request_coalesced);
    PERFORMANCE_METRICS_RESET(render_tasks);
    PERFORMANCE_METRICS_RESET(render_queue_wait_total_us);
    PERFORMANCE_METRICS_RESET(render_queue_wait_max_us);
    PERFORMANCE_METRICS_RESET(mpv_render_calls);
    PERFORMANCE_METRICS_RESET(skip_rendering_calls);
    PERFORMANCE_METRICS_RESET(mpv_render_total_us);
    PERFORMANCE_METRICS_RESET(mpv_render_max_us);
    PERFORMANCE_METRICS_RESET(producer_commits);
    PERFORMANCE_METRICS_RESET(producer_commit_failures);
    PERFORMANCE_METRICS_RESET(frame_available_marks);
    PERFORMANCE_METRICS_RESET(frame_available_failures);
    PERFORMANCE_METRICS_RESET(frame_available_total_us);
    PERFORMANCE_METRICS_RESET(frame_available_max_us);
    PERFORMANCE_METRICS_RESET(flutter_texture_callbacks);
    PERFORMANCE_METRICS_RESET(flutter_texture_callback_total_us);
    PERFORMANCE_METRICS_RESET(flutter_texture_callback_max_us);
    PERFORMANCE_METRICS_RESET(consumer_acquire_calls);
    PERFORMANCE_METRICS_RESET(consumer_acquire_total_us);
    PERFORMANCE_METRICS_RESET(consumer_acquire_max_us);
    PERFORMANCE_METRICS_RESET(texture_callback_no_handle);
    PERFORMANCE_METRICS_RESET(texture_handle_changes);
    PERFORMANCE_METRICS_RESET(texture_registrations);
    PERFORMANCE_METRICS_RESET(texture_resizes);
    PERFORMANCE_METRICS_RESET(texture_unregisters);
    PERFORMANCE_METRICS_RESET(flushes);
    PERFORMANCE_METRICS_RESET(blocking_fence_waits);
    PERFORMANCE_METRICS_RESET(blocking_wait_total_us);
    PERFORMANCE_METRICS_RESET(blocking_wait_max_us);
    PERFORMANCE_METRICS_RESET(nonblocking_fence_polls);
    PERFORMANCE_METRICS_RESET(nonblocking_fence_incomplete);
    PERFORMANCE_METRICS_RESET(publishes);
    PERFORMANCE_METRICS_RESET(pending_slots_current);
    PERFORMANCE_METRICS_RESET(pending_slots_max);
    PERFORMANCE_METRICS_RESET(mailbox_full);
    PERFORMANCE_METRICS_RESET(fixed_handle_copies);
    PERFORMANCE_METRICS_RESET(render_target_misses);
#undef PERFORMANCE_METRICS_RESET
    for (auto& bucket : mpv_render_buckets_) {
      bucket.store(0, std::memory_order_relaxed);
    }
  }

  std::atomic<bool> enabled_{false};
  std::atomic<uint64_t> enabled_since_tick_{0};
  std::atomic<int> output_mode_{-1};
  std::atomic<int> active_outputs_{0};
  std::atomic<bool> hardware_acceleration_{false};
  std::atomic<bool> anime4k_enabled_{false};
  std::atomic<int64_t> texture_width_{0};
  std::atomic<int64_t> texture_height_{0};
  std::atomic<int64_t> window_width_{0};
  std::atomic<int64_t> window_height_{0};
  std::atomic<int> display_dpi_{0};
  std::atomic<int> display_refresh_rate_{0};
  std::atomic<int> gpu_priority_requested_{0};
  std::atomic<int> gpu_priority_applied_{0};
  std::atomic<long> gpu_priority_hresult_{0};
  mutable std::mutex metadata_mutex_;
  std::string render_backend_;
  std::string gpu_adapter_;

#define PERFORMANCE_METRICS_COUNTER(field) std::atomic<uint64_t> field##_{0}
  PERFORMANCE_METRICS_COUNTER(render_requests);
  PERFORMANCE_METRICS_COUNTER(render_request_coalesced);
  PERFORMANCE_METRICS_COUNTER(render_tasks);
  PERFORMANCE_METRICS_COUNTER(render_queue_wait_total_us);
  PERFORMANCE_METRICS_COUNTER(render_queue_wait_max_us);
  PERFORMANCE_METRICS_COUNTER(mpv_render_calls);
  PERFORMANCE_METRICS_COUNTER(skip_rendering_calls);
  PERFORMANCE_METRICS_COUNTER(mpv_render_total_us);
  PERFORMANCE_METRICS_COUNTER(mpv_render_max_us);
  PERFORMANCE_METRICS_COUNTER(producer_commits);
  PERFORMANCE_METRICS_COUNTER(producer_commit_failures);
  PERFORMANCE_METRICS_COUNTER(frame_available_marks);
  PERFORMANCE_METRICS_COUNTER(frame_available_failures);
  PERFORMANCE_METRICS_COUNTER(frame_available_total_us);
  PERFORMANCE_METRICS_COUNTER(frame_available_max_us);
  PERFORMANCE_METRICS_COUNTER(flutter_texture_callbacks);
  PERFORMANCE_METRICS_COUNTER(flutter_texture_callback_total_us);
  PERFORMANCE_METRICS_COUNTER(flutter_texture_callback_max_us);
  PERFORMANCE_METRICS_COUNTER(consumer_acquire_calls);
  PERFORMANCE_METRICS_COUNTER(consumer_acquire_total_us);
  PERFORMANCE_METRICS_COUNTER(consumer_acquire_max_us);
  PERFORMANCE_METRICS_COUNTER(texture_callback_no_handle);
  PERFORMANCE_METRICS_COUNTER(texture_handle_changes);
  PERFORMANCE_METRICS_COUNTER(texture_registrations);
  PERFORMANCE_METRICS_COUNTER(texture_resizes);
  PERFORMANCE_METRICS_COUNTER(texture_unregisters);
  PERFORMANCE_METRICS_COUNTER(flushes);
  PERFORMANCE_METRICS_COUNTER(blocking_fence_waits);
  PERFORMANCE_METRICS_COUNTER(blocking_wait_total_us);
  PERFORMANCE_METRICS_COUNTER(blocking_wait_max_us);
  PERFORMANCE_METRICS_COUNTER(nonblocking_fence_polls);
  PERFORMANCE_METRICS_COUNTER(nonblocking_fence_incomplete);
  PERFORMANCE_METRICS_COUNTER(publishes);
  PERFORMANCE_METRICS_COUNTER(pending_slots_current);
  PERFORMANCE_METRICS_COUNTER(pending_slots_max);
  PERFORMANCE_METRICS_COUNTER(mailbox_full);
  PERFORMANCE_METRICS_COUNTER(fixed_handle_copies);
  PERFORMANCE_METRICS_COUNTER(render_target_misses);
#undef PERFORMANCE_METRICS_COUNTER
  std::atomic<uint64_t> mpv_render_buckets_[7] = {};
};

}  // namespace media_kit_video

#endif  // PERFORMANCE_METRICS_H_

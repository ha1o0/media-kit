import Darwin
import Foundation

#if SWIFT_PACKAGE
  import Mpv
#endif

public enum MPVHelpers {
  #if os(iOS)
    // Called on the owning render worker (and with the current EAGL context
    // for GLES). A new context can request dummy redraws before video exists.
    // Consume any queued redraw without letting it replace the held PiP frame.
    static func prepareDecodedPictureInPictureFrame(_ context: OpaquePointer) -> Bool {
      var info = mpv_render_frame_info()
      let status = withUnsafeMutablePointer(to: &info) { pointer in
        mpv_render_context_get_info(context, mpv_render_param(
          type: MPV_RENDER_PARAM_NEXT_FRAME_INFO, data: UnsafeMutableRawPointer(pointer)))
      }
      guard status >= 0 else { return false }
      let present = info.flags & UInt64(MPV_RENDER_FRAME_INFO_PRESENT.rawValue) != 0
      guard present else { return false }
      if PictureInPictureFrameHandoff.isDecodedFrame(
        present: present,
        redraw: info.flags & UInt64(MPV_RENDER_FRAME_INFO_REDRAW.rawValue) != 0,
        repeated: info.flags & UInt64(MPV_RENDER_FRAME_INFO_REPEAT.rawValue) != 0
      ) { return true }

      var skip: Int32 = 1
      var block: Int32 = 0
      withUnsafeMutablePointer(to: &skip) { skipPointer in
        withUnsafeMutablePointer(to: &block) { blockPointer in
          var params = [
            mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: UnsafeMutableRawPointer(skipPointer)),
            mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: UnsafeMutableRawPointer(blockPointer)),
            mpv_render_param(),
          ]
          _ = mpv_render_context_render(context, &params)
        }
      }
      return false
    }
  #endif

  public static func checkError(_ status: CInt) {
    if status < 0 {
      NSLog("MPVHelpers: error: \(String(cString: mpv_error_string(status)))")
      exit(1)
    }
  }

  public static func getVideoOutParams(
    _ handle: OpaquePointer
  ) -> MPVVideoOutParams {
    var node = mpv_node()
    defer {
      mpv_free_node_contents(&node)
    }

    mpv_get_property(handle, "video-out-params", MPV_FORMAT_NODE, &node)

    if node.format != MPV_FORMAT_NODE_MAP {
      return MPVVideoOutParams.empty
    }

    let map: mpv_node_list = node.u.list!.pointee
    if map.num == 0 {
      return MPVVideoOutParams.empty
    }

    return MPVVideoOutParams.fromMPVNodeList(map)
  }
}

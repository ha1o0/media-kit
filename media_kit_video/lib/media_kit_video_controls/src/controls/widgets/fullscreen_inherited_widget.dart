/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/video_state.dart';

/// {@template fullscreen_inherited_widget}
///
/// Inherited widget used to identify whether parent [Video] is in fullscreen or not.
///
/// {@endtemplate}
class FullscreenInheritedWidget extends InheritedWidget {
  final VideoState parent;

  FullscreenInheritedWidget({
    super.key,
    required this.parent,
    required Widget child,
  }) : super(child: _FullscreenInheritedWidgetPopScope(child: child));

  static FullscreenInheritedWidget? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FullscreenInheritedWidget>();
  }

  static FullscreenInheritedWidget of(BuildContext context) {
    final FullscreenInheritedWidget? result = maybeOf(context);
    assert(
      result != null,
      'No [FullscreenInheritedWidget] found in [context]',
    );
    return result!;
  }

  @override
  bool updateShouldNotify(FullscreenInheritedWidget oldWidget) =>
      identical(parent, oldWidget.parent);
}

/// {@template fullscreen_inherited_widget_pop_scope}
///
/// This widget is used to exit native fullscreen when this route is popped from the navigator.
///
/// {@endtemplate}
class _FullscreenInheritedWidgetPopScope extends StatefulWidget {
  final Widget child;
  const _FullscreenInheritedWidgetPopScope({
    required this.child,
  });

  @override
  State<_FullscreenInheritedWidgetPopScope> createState() =>
      _FullscreenInheritedWidgetPopScopeState();
}

class _FullscreenInheritedWidgetPopScopeState
    extends State<_FullscreenInheritedWidgetPopScope> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, __) {
        // Restore the source Video's native-window ownership even when the
        // route is dismissed by Escape, the system back action or Navigator.
        FullscreenInheritedWidget.of(context)
            .parent
            .setNativeFullscreenRouteActive(false);
        // Make sure to exit native fullscreen when this route is popped from the navigator.
        final callback = onExitFullscreen(context);
        if (callback != null) {
          unawaited(Future.sync(callback).catchError((error) {
            if (kDebugMode) {
              debugPrint('Error exiting fullscreen on pop: $error');
            }
          }));
        }
      },
      child: widget.child,
    );
  }
}

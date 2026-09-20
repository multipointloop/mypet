import 'dart:async';
import 'dart:ffi' as dffi;
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:win32/win32.dart';

/// Adaptive-frequency global cursor tracker.
///
/// * 60 fps while the mouse is moving  -> smooth gaze tracking
/// * 11 fps after 500 ms of stillness  -> near-zero CPU cost when idle
///
/// Coordinates are converted from physical px to logical px using the
/// primary Flutter view's devicePixelRatio.
class CursorPoller {
  void Function(Offset logicalPos)? onCursor;

  /// Most recent cursor position in logical px (also the source for
  /// cursor-driven window dragging).
  Offset lastLogical = Offset.zero;

  Timer? _timer;
  Duration _period = const Duration(milliseconds: 16);
  Offset _last = Offset.zero;
  DateTime _lastMove = DateTime.now();
  double _dpr = 1;

  Future<void> start() async {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      _dpr = views.isNotEmpty ? views.first.devicePixelRatio : 1;
    } catch (_) {
      _dpr = 1;
    }
    _schedule(const Duration(milliseconds: 16));
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, _tick);
  }

  void _tick() {
    final pt = calloc.allocate<POINT>(dffi.sizeOf<POINT>());
    try {
      if (GetCursorPos(pt) != 0) {
        final logical = Offset(pt.ref.x / _dpr, pt.ref.y / _dpr);
        lastLogical = logical;
        if ((logical - _last).distance > 0.5) {
          _last = logical;
          _lastMove = DateTime.now();
          _period = const Duration(milliseconds: 16);
        } else if (DateTime.now().difference(_lastMove).inMilliseconds > 500) {
          _period = const Duration(milliseconds: 90);
        }
        onCursor?.call(logical);
      }
    } finally {
      calloc.free(pt);
    }
    _schedule(_period);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

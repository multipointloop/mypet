import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Android floating window management + the settings<->overlay data link.
/// flutter_overlay_window 0.4.5 exposes a static-only API.
class OverlayService {
  OverlayService._();

  /// Settings page -> overlay pet command stream.
  static void Function(Map<dynamic, dynamic> msg)? _onMsg;

  static Future<bool> isPermissionGranted() async =>
      FlutterOverlayWindow.isPermissionGranted();

  static Future<void> requestPermission() async {
    await FlutterOverlayWindow.requestPermission();
  }

  /// Show the pet overlay near the bottom of the screen.
  /// enableDrag lets the user drag the pet anywhere; the system handles the
  /// move so the app never fights the window manager.
  static Future<void> show({required double petW, required double petH}) async {
    await FlutterOverlayWindow.showOverlay(
      height: (petH + 48).toInt(),
      width: (petW + 24).toInt(),
      alignment: OverlayAlignment.bottomCenter,
      flag: OverlayFlag.defaultFlag,
      overlayTitle: 'MyPet 桌宠运行中',
      overlayContent: '点按宠物返回设置',
      enableDrag: true,
      positionGravity: PositionGravity.none,
      visibility: NotificationVisibility.visibilityPublic,
    );
  }

  static Future<void> close() => FlutterOverlayWindow.closeOverlay();

  static Future<void> resize({required double w, required double h}) =>
      FlutterOverlayWindow.resizeOverlay(w.toInt(), h.toInt(), true);

  static Future<void> send(Map<String, dynamic> msg) =>
      FlutterOverlayWindow.shareData(msg);

  /// Subscribe to messages coming from the settings page (main isolate).
  static void listenSettings(void Function(Map<dynamic, dynamic>) cb) {
    if (_onMsg != null) return;
    _onMsg = cb;
    FlutterOverlayWindow.overlayListener.listen((dynamic msg) {
      if (msg is Map) cb(msg);
    });
  }
}

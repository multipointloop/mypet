import 'package:flutter/services.dart';

/// Bridge to the native C++ layer in windows/runner:
///  * setKeyHook(bool)  - enable/disable the WH_KEYBOARD_LL hook (Bongo Cat),
///                        OFF by default (AV / anti-cheat friendliness)
///  * onKey             - pushed key events {vk: int, name: String, down: bool}
///  * onHotkey          - registered hotkeys Ctrl+Alt+Up (0) / Down (1)
class NativeChannel {
  NativeChannel._();
  static final NativeChannel instance = NativeChannel._();

  static const _ch = MethodChannel('mypet/native');

  void Function(String keyName, bool down)? onKey;
  void Function(int hotkeyId)? onHotkey;
  void Function(int itemId)? onQuickMenu;

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onKey':
          final args = call.arguments as Map?;
          final name = args?['name'] as String? ?? '';
          final down = args?['down'] as bool? ?? false;
          if (name.isNotEmpty) onKey?.call(name, down);
        case 'onHotkey':
          final id = (call.arguments as Map?)?['id'] as int? ?? -1;
          onHotkey?.call(id);
        case 'onQuickMenu':
          final id = (call.arguments as Map?)?['id'] as int? ?? -1;
          onQuickMenu?.call(id);
      }
      return null;
    });
  }

  /// 图标右键的原生简易调整栏（放大/缩小/穿透/设置面板/退出）。
  Future<void> showQuickMenu() async {
    try {
      await _ch.invokeMethod('showQuickMenu');
    } on MissingPluginException {
      // non-windows runner (tests); ignore
    }
  }

  Future<void> setKeyHook(bool enabled) async {
    try {
      await _ch.invokeMethod('setKeyHook', {'enabled': enabled});
    } on MissingPluginException {
      // non-windows runner (tests); ignore
    }
  }

  /// Push the click-through hit-test layout to the C++ layer.
  /// [pet]/[button] are window-local PHYSICAL px rects; [full] makes every
  /// pixel except the button pass clicks through.
  Future<void> setHitTest({
    required bool full,
    required List<double> pet,
    required List<double> button,
    required List<double> band,
    required bool bandOn,
  }) async {
    try {
      await _ch.invokeMethod('setHitTest', {
        'full': full,
        'pet': pet,
        'button': button,
        'band': band,
        'bandOn': bandOn,
      });
    } on MissingPluginException {
      // non-windows runner (tests); ignore
    }
  }
}

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:system_tray/system_tray.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/trace.dart';
import '../../features/pet/pet_engine.dart';
import 'native_channel.dart';

/// Owns the Windows shell around the pet: transparent frameless window,
/// always-on-top, click-through, tray menu, auto start, work-area lookup.
class WindowsWindowService {
  WindowsWindowService._();
  static final WindowsWindowService instance = WindowsWindowService._();

  PetEngine? _engine;
  final SystemTray _tray = SystemTray();

  // callbacks wired by the pet widget
  void Function(double delta)? onScaleDelta; // +0.1 / -0.1
  void Function()? onToggleClickThrough;
  void Function()? onToggleBongo;
  void Function()? onToggleSettings;
  void Function()? onQuit;

  bool _autostartReady = false;

  void attachEngine(PetEngine engine) => _engine = engine;

  /// Transparent frameless always-on-top window, hidden from taskbar.
  Future<void> boot() async {
    await acrylic.Window.initialize();
    await windowManager.ensureInitialized();

    await acrylic.Window.setEffect(
      effect: acrylic.WindowEffect.transparent,
      color: Colors.transparent,
    );

    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(300, 480),
        backgroundColor: Colors.transparent,
        skipTaskbar: true,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      ),
      () async {
        await windowManager.setAsFrameless();
        await windowManager.setBackgroundColor(Colors.transparent);
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show();
      },
    );
  }

  /// Resize window for a new pet scale, keeping the feet position stable.
  /// The very first call docks the pet to the bottom-right of the work area.
  Future<void> resizeToPet(double petScale) async {
    final engine = _engine;
    if (engine == null || engine.rig == null) return;
    final r = engine.rig!;
    final winW = r.canvasW * engine.scale + 20; // kSidePad * 2
    final winH = r.canvasH * engine.scale + 120; // kBubbleSpace

    Trace.log('resizeToPet enter scale=$petScale');
    final old = await windowManager.getPosition();
    Trace.log('resizeToPet got pos=$old');
    final area = await workAreaRectLogical();
    Trace.log('resizeToPet got area=${area.bottom}');
    final Offset pos;
    if (!_placedOnce) {
      pos = Offset(area.right - winW - 60, area.bottom - winH - 8);
      _placedOnce = true;
    } else {
      pos = Offset(old.dx, old.dy + (engine.windowH - winH));
    }
    Trace.log('resizeToPet before setSize ${winW}x$winH');
    await windowManager.setSize(Size(winW, winH));
    Trace.log('resizeToPet after setSize');
    engine.windowW = winW;
    engine.windowH = winH;
    await windowManager.setPosition(pos);
    Trace.log('resizeToPet after setPosition');
    engine.windowPos = pos;
    engine.groundY = area.bottom - winH;
    Trace.log('resizeToPet done');
  }

  bool _placedOnce = false;

  Future<void> moveWindow(Offset logicalPos) async {
    await windowManager.setPosition(logicalPos);
    _engine?.windowPos = logicalPos;
  }

  /// Click-through is implemented with per-region WM_NCHITTEST (C++ side):
  /// the pet body and the toggle button stay clickable, everything else lets
  /// clicks fall through. [fullPassthrough] collapses the clickable area to
  /// just the toggle button so the user can always turn it back off.
  Future<void> setClickThrough(bool enabled) async {
    Trace.log('setClickThrough $enabled');
    await _pushHitTest(fullPassthrough: enabled);
    Trace.log('setClickThrough pushed');
  }

  /// Whole-window alpha (normal vs click-through ghosting).
  Future<void> setOpacity(double opacity) async {
    Trace.log('setOpacity $opacity');
    try {
      await windowManager.setOpacity(opacity.clamp(0.1, 1.0));
    } catch (_) {
      // opacity is cosmetic - never fail on it
    }
  }

  Rect? _petRect;   // window-local logical px
  Rect? _buttonRect;

  Future<void> setHitTestRegions({
    required Rect pet,
    required Rect button,
    bool fullPassthrough = false,
  }) async {
    _petRect = pet;
    _buttonRect = button;
    await _pushHitTest(fullPassthrough: fullPassthrough);
  }

  Future<void> _pushHitTest({required bool fullPassthrough}) async {
    final pet = _petRect;
    final button = _buttonRect;
    if (pet == null || button == null) return;
    final dpr = _engine?.devicePixelRatio ?? 1;
    await NativeChannel.instance.setHitTest(
      full: fullPassthrough,
      pet: [
        pet.left * dpr, pet.top * dpr, pet.right * dpr, pet.bottom * dpr,
      ],
      button: [
        button.left * dpr, button.top * dpr,
        button.right * dpr, button.bottom * dpr,
      ],
    );
  }

  Future<void> setBongoHook(bool enabled) async {
    await NativeChannel.instance.setKeyHook(enabled);
  }

  Future<void> setAutostart(bool enabled) async {
    if (!_autostartReady) {
      launchAtStartup.setup(
        appName: 'mypet',
        appPath: Platform.resolvedExecutable,
        args: [],
      );
      _autostartReady = true;
    }
    if (enabled) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }

  /// Primary monitor work area (excludes taskbar) in logical px.
  Future<Rect> workAreaRectLogical() async {
    final rect = calloc.allocate<RECT>(ffi.sizeOf<RECT>());
    try {
      // SPI_GETWORKAREA = 0x0030
      if (SystemParametersInfo(SPI_GETWORKAREA, 0, rect.cast<ffi.Void>(), 0) !=
          0) {
        final dpr = _engine?.devicePixelRatio ?? 1;
        return Rect.fromLTRB(rect.ref.left / dpr, rect.ref.top / dpr,
            rect.ref.right / dpr, rect.ref.bottom / dpr);
      }
    } finally {
      calloc.free(rect);
    }
    return const Rect.fromLTRB(0, 0, 1920, 1040);
  }

  Future<void> initTray() async {
    try {
      await _tray.initSystemTray(
        title: 'MyPet',
        iconPath: 'assets/icon/tray.ico',
        toolTip: 'MyPet 桌宠',
      );

      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: 'MyPet 猫娘桌宠', enabled: false),
        MenuSeparator(),
        MenuItemLabel(label: '放大  (Ctrl+Alt+↑)', onClicked: (_) => _fireScaleUp()),
        MenuItemLabel(label: '缩小  (Ctrl+Alt+↓)', onClicked: (_) => _fireScaleDown()),
        MenuItemLabel(label: '鼠标穿透  (Ctrl+Alt+T)',
            onClicked: (_) => _fireClickThrough()),
        MenuSeparator(),
        MenuItemLabel(label: '设置面板', onClicked: (_) => _fireSettings()),
        MenuItemLabel(label: '退出', onClicked: (_) => _fireQuit()),
      ]);
      await _tray.setContextMenu(menu);

      _tray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) {
          _tray.popUpContextMenu();
        } else if (eventName == kSystemTrayEventDoubleClick) {
          _fireSettings();
        }
      });
    } catch (_) {
      // tray icon is cosmetic; never block startup over it
    }
  }

  // dynamic click-through / bongo items are managed by rebuilding the menu
  void _fireScaleUp() => onScaleDelta?.call(0.1);
  void _fireClickThrough() => onToggleClickThrough?.call();
  void _fireScaleDown() => onScaleDelta?.call(-0.1);
  void _fireSettings() => onToggleSettings?.call();
  void _fireQuit() => onQuit?.call();

  Future<void> disposeTray() => _tray.destroy();
}


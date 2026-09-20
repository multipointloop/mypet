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
        await windowManager.setResizable(false);
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
    Trace.log('resizeToPet got pos=${old.dx.toStringAsFixed(0)},${old.dy.toStringAsFixed(0)}');
    final area = await workAreaRectLogical();
    Trace.log('resizeToPet got area=${area.bottom}');
    final Offset pos;
    if (!_placedOnce) {
      pos = Offset(area.right - winW - 60,
          (area.bottom - winH - 8).clamp(area.top, area.bottom - winH).toDouble());
      _placedOnce = true;
    } else {
      pos = Offset(old.dx,
          (old.dy + (engine.windowH - winH)).clamp(area.top, area.bottom - winH).toDouble());
    }
    Trace.log('resizeToPet before setSize ${winW}x$winH');
    await windowManager.setSize(Size(winW, winH));
    Trace.log('resizeToPet after setSize');
    engine.windowW = winW;
    engine.windowH = winH;
    await windowManager.setPosition(pos);
    Trace.log('resizeToPet after setPosition');
    engine.windowPos = pos;
    // 地面线 = 工作区底边；落地位置由 _stepPhysics 换算为 groundY - windowH
    engine.groundY = area.bottom;
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
    if (_panelMode) {
      // 面板期间只写 Config：立刻推 fullPassthrough 会让面板自己失去点击
      Trace.log('setClickThrough deferred (panel open)');
      return;
    }
    await _pushHitTest(fullPassthrough: enabled);
    Trace.log('setClickThrough pushed');
  }

  /// Whole-window alpha (normal vs click-through ghosting).
  Future<void> setOpacity(double opacity) async {
    Trace.log('setOpacity $opacity panel=$_panelMode');
    try {
      final target = _panelMode ? 1.0 : opacity.clamp(0.1, 1.0);
      await windowManager.setOpacity(target);
    } catch (_) {
      // opacity is cosmetic - never fail on it
    }
  }

  Rect? _petRect;   // window-local logical px
  Rect? _buttonRect;
  Rect? _bandRect;
  bool _bandOn = false;

  Future<void> setHitTestRegions({
    required Rect pet,
    required Rect button,
    Rect? band,
    bool bandOn = false,
    bool fullPassthrough = false,
  }) async {
    _petRect = pet;
    _buttonRect = button;
    _bandRect = band;
    _bandOn = bandOn;
    if (_panelMode) return; // 面板期间保持整窗可交互
    await _pushHitTest(fullPassthrough: fullPassthrough);
  }

  Future<void> _pushHitTest({required bool fullPassthrough}) async {
    final pet = _petRect;
    final button = _buttonRect;
    if (pet == null || button == null) return;
    final dpr = _engine?.devicePixelRatio ?? 1;
    final band = _bandRect ?? Rect.zero;
    await NativeChannel.instance.setHitTest(
      full: fullPassthrough,
      pet: [
        pet.left * dpr, pet.top * dpr, pet.right * dpr, pet.bottom * dpr,
      ],
      button: [
        button.left * dpr, button.top * dpr,
        button.right * dpr, button.bottom * dpr,
      ],
      band: [
        band.left * dpr, band.top * dpr, band.right * dpr, band.bottom * dpr,
      ],
      bandOn: _bandOn && !fullPassthrough,
    );
  }

  // ================= 设置面板形态（单窗口双形态） =================
  //
  // 宠物形态：透明/无框/置顶/区域级穿透，尺寸随 petScale 变化。
  // 面板形态：固定尺寸/居中/整窗可交互/不透明，尺寸与兽形解耦。
  // 切换过程中刻意**不触碰 acrylic 透明效果**（减少 DWM 重设面）。

  static const Size panelSize = Size(640, 460);
  static const double _kSidePad = 10;
  static const double _kBubbleSpace = 120;

  bool _panelMode = false;
  bool get panelMode => _panelMode;
  Rect? _savedPetBounds;
  bool _savedPhysics = false;

  /// 进入面板形态：暂存宠物 bounds -> 暂停落体 -> 整窗可交互 -> 固定尺寸居中。
  Future<void> enterPanelMode() async {
    if (_panelMode) return;
    _panelMode = true;
    Trace.log('enterPanelMode');

    final e = _engine;
    final pos = await windowManager.getPosition();
    final size = await windowManager.getSize();
    _savedPetBounds = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
    Trace.log('enterPanelMode saved='
        '${pos.dx.toStringAsFixed(0)},${pos.dy.toStringAsFixed(0)} '
        '${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}');

    if (e != null) {
      // 加固点 1：面板开着时停止落体，否则 _stepPhysics 会把面板窗口自己拖下去
      _savedPhysics = e.physicsActive;
      e.physicsActive = false;
      e.dragActive = false;
      e.windowVel = Offset.zero;
    }

    // 加固点 2：整窗可交互（否则 C++ 区域 hit-test 把面板点击全部放行到桌面）
    final dpr = e?.devicePixelRatio ?? 1;
    await NativeChannel.instance.setHitTest(
      full: false,
      pet: [0, 0, panelSize.width * dpr, panelSize.height * dpr],
      button: const [0, 0, 0, 0],
      band: const [0, 0, 0, 0],
      bandOn: false,
    );

    await windowManager.setOpacity(1.0);
    await windowManager.setSize(panelSize);
    await windowManager.center();
    await windowManager.focus();
    await windowManager.setAlwaysOnTop(true);
    Trace.log('enterPanelMode done');
  }

  /// 退出面板形态。
  /// [applyPetResize] = 面板期间是否改过尺寸；改过则按"脚底不动"重算高度。
  /// 这里直接还原 bounds 并回写引擎几何，绕开 resizeToPet 的首次停靠逻辑。
  Future<void> exitPanelMode({required bool applyPetResize}) async {
    if (!_panelMode) return;
    _panelMode = false;
    Trace.log('exitPanelMode applyPetResize=$applyPetResize');

    final e = _engine;
    final b = _savedPetBounds;
    _savedPetBounds = null;

    if (b != null && e != null) {
      var w = b.width;
      var h = b.height;
      if (applyPetResize) {
        final r = e.rig;
        if (r != null) {
          w = r.canvasW * e.scale + _kSidePad * 2;
          h = r.canvasH * e.scale + _kBubbleSpace;
        }
      }
      // 加固点 4：脚底不动 —— 变高向上长，变矮向下收；并夹在工作区内
      final area = await workAreaRectLogical();
      final top = (b.top + (b.height - h))
          .clamp(area.top, area.bottom - h)
          .toDouble();
      await windowManager.setSize(Size(w, h));
      await windowManager.setPosition(Offset(b.left, top));
      e.windowW = w;
      e.windowH = h;
      e.windowPos = Offset(b.left, top);
      e.groundY = area.bottom;
      Trace.log('exitPanelMode restored='
          '${b.left.toStringAsFixed(0)},${top.toStringAsFixed(0)} '
          '${w.toStringAsFixed(0)}x${h.toStringAsFixed(0)}');
      if (_savedPhysics) e.startFall();
    }

    await _pushHitTest(fullPassthrough: false);
    Trace.log('exitPanelMode done');
  }

  Future<void> setBongoHook(bool enabled) async {
    await NativeChannel.instance.setKeyHook(enabled);
  }

  /// 重新声明置顶：Alt+Tab / 有其它置顶窗口抢层时，先摘再置可以把我们抬回最上。
  Future<void> reassertTopMost() async {
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setAlwaysOnTop(true);
    } catch (_) {
      // 置顶是增强项，失败不影响主流程
    }
  }

  bool? _autostartApplied;

  Future<void> setAutostart(bool enabled) async {
    if (_autostartApplied == enabled) return; // 幂等：面板高频回调不重复写注册表
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
    _autostartApplied = enabled;
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
        // 左键单击 = 打开/关闭设置面板（与常见应用一致）
        if (eventName == kSystemTrayEventClick) {
          _fireSettings();
        } else if (eventName == kSystemTrayEventDoubleClick) {
          // 双击兜底：部分系统把两次单击合成为双击
          _fireSettings();
        } else if (eventName == kSystemTrayEventRightClick) {
          // 右键 = 图标处的简易调整栏（放大/缩小/鼠标穿透/设置面板/退出）
          _tray.popUpContextMenu();
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


import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:window_manager/window_manager.dart';

import '../../core/audio_service.dart';
import '../../core/config.dart';
import '../../core/rig_model.dart';
import '../../core/rig_view.dart';
import '../../platform/android/overlay_service.dart';
import '../../platform/win/cursor_poller.dart';
import '../../platform/win/native_channel.dart';
import '../../platform/win/window_service.dart';
import 'dialogue_bubble.dart';
import 'pet_engine.dart';
import '../../core/trace.dart';
import '../settings/settings_panel.dart';

/// Layout constants (logical px at petScale = 1.0).
const double kBasePetWidth = 260;
const double kBubbleSpace = 120;
const double kSidePad = 10;

/// 穿透开关（小眼睛）按钮：锚在头部图层右上角外侧，随缩放移动。
/// 间距按 5mm 估算（96dpi 下约 19 逻辑像素），用下面两个常量微调。
const double kButtonSize = 30;
const double kButtonGapX = 19;
const double kButtonGapY = 19;

/// Windows: transparent always-on-top pet window.
class WindowsPetHome extends StatefulWidget {
  const WindowsPetHome({super.key});

  @override
  State<WindowsPetHome> createState() => _WindowsPetHomeState();
}

class _WindowsPetHomeState extends State<WindowsPetHome> with WindowListener {
  final PetEngine engine = PetEngine();
  final CursorPoller poller = CursorPoller();
  RigData? rig;
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (_booted) return;
    _booted = true;
    final cfg = Config.instance;
    await cfg.load();
    await AudioService.instance.preload();
    rig = await RigData.load(readAsset: rootBundle.loadString);
    engine.rig = rig;

    // attach engine BEFORE anything that resizes/positions the window
    final win = WindowsWindowService.instance;
    win.attachEngine(engine);
    // logical<->physical conversions (SPI work area, GetCursorPos) need the
    // real DPI factor, otherwise window placement lands off-screen at >100%
    // display scaling
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      engine.devicePixelRatio = views.isNotEmpty ? views.first.devicePixelRatio : 1;
    } catch (_) {
      engine.devicePixelRatio = 1;
    }
    // drag/fall move the window through the engine's once-per-tick bridge
    engine.onWindowMoveRequested =
        (p) => WindowsWindowService.instance.moveWindow(p);
    await _refreshMaxScale(); // 先算本机可容纳的最大尺寸，再应用
    await _applyScale(cfg.petScale);
    _pushHitTestRegions();

    win.onScaleDelta = (delta) =>
        _applyScale((cfg.petScale + delta).clamp(0.35, _maxPetScale));
    win.onToggleClickThrough = () => _toggleClickThrough();
    win.onToggleBongo = () {
      cfg.setBongoHook(!cfg.bongoHook);
      cfg.applyToPlatform();
      setState(() {});
    };
    win.onToggleSettings = () => _toggleSettings();
    win.onQuit = () => windowManager.destroy();
    await win.initTray();

    NativeChannel.instance.onKey = (vk, down) {
      if (!cfg.bongoHook || !down) return;
      const leftKeys = {
        'A', 'Q', 'W', 'S', 'Z', 'X', 'Shift', 'CapsLock', '1', '2', 'Tab',
      };
      engine.bongoTap(left: leftKeys.contains(vk));
    };
    NativeChannel.instance.onHotkey = (id) {
      if (id == 0) {
        _applyScale((cfg.petScale + 0.1).clamp(0.35, _maxPetScale));
      } else if (id == 1) {
        _applyScale((cfg.petScale - 0.1).clamp(0.35, _maxPetScale));
      } else if (id == 3) {
        _toggleSettings();
      } else if (id == 2) {
        // Ctrl+Alt+T: click-through toggle (also the way OUT, since in
        // passthrough mode only the on-pet button stays clickable)
        _toggleClickThrough();
      }
    };
    await NativeChannel.instance.start();

    windowManager.addListener(this);
    _topGuard = Timer.periodic(const Duration(seconds: 10), (_) {
      WindowsWindowService.instance.reassertTopMost();
    });

    poller.onCursor = (logicalPos) {
      final eye = _eyeAnchorScreen();
      if (eye != null) engine.feedPointer(logicalPos, eye, 360 * engine.scale);
    };
    await poller.start();

    engine.start();
    if (mounted) setState(() {});
  }

  bool _panelOpen = false;
  bool _applyingScale = false;
  double? _pendingScale;

  Timer? _topGuard;

  @override
  void onWindowFocus() => _reassert('focus');

  @override
  void onWindowBlur() => _reassert('blur');

  @override
  void onWindowRestore() => _reassert('restore');

  /// Alt+Tab / 唤醒后：其它置顶窗口可能把我们顶下去，系统也可能重置窗口区域。
  /// 这里重新声明置顶并补推一次区域（幂等，只有两次系统调用）。
  void _reassert(String why) {
    Trace.log('reassert topMost ($why)');
    WindowsWindowService.instance.reassertTopMost();
    if (!WindowsWindowService.instance.panelMode) _pushHitTestRegions();
  }

  double _panelOpenedScale = 1.0;

  /// 本机工作区能容纳的最大 petScale（窗口高 = canvasH*scale + 气泡区）。
  /// 超出后窗口必然高过屏幕，宠物腿部会被切掉，因此把它作为滑杆上限。
  double _maxPetScale = 2.5;
  Future<void> _refreshMaxScale() async {
    final r = rig;
    if (r == null) return;
    final area = await WindowsWindowService.instance.workAreaRectLogical();
    final perUnit = r.canvasH * (kBasePetWidth / r.canvasW);
    final fit = (area.height - kBubbleSpace - 8) / perUnit;
    final clamped = fit.clamp(0.35, 2.5).toDouble();
    if (mounted) setState(() => _maxPetScale = clamped);
  }

  void _toggleSettings() {
    if (_panelOpen) {
      _closeSettings();
    } else {
      _openSettings();
    }
  }

  /// 进入设置形态：UI 先切到面板，再把窗口改成固定尺寸/居中/整窗可交互。
  Future<void> _openSettings() async {
    if (_panelOpen) return;
    _panelOpenedScale = Config.instance.petScale;
    setState(() => _panelOpen = true);
    await WindowsWindowService.instance.enterPanelMode();
  }

  /// 退出设置形态：先按"脚底不动"还原窗口，再恢复宠物交互区域与穿透/透明度。
  /// 穿透的 hit-test 推送被推迟到这里（window_service 里对面板态做了闸门）。
  Future<void> _closeSettings() async {
    if (!_panelOpen) return;
    final changed =
        (Config.instance.petScale - _panelOpenedScale).abs() > 0.0001;
    await WindowsWindowService.instance.exitPanelMode(applyPetResize: changed);
    if (!mounted) return;
    setState(() => _panelOpen = false);
    _pushHitTestRegions();
    await Config.instance.applyToPlatform();
  }

  /// 面板内改动即时下推平台（音效/音量/Bongo/自启…）。
  /// 重操作已幂等（见 setAutostart），因此此处不做节流，避免吞掉快速连点的开关。
  void _applyConfigChange() {
    Config.instance.applyToPlatform();
    if (mounted) setState(() {});
  }

  /// 面板内拖尺寸滑杆：只更新配置与右侧实时预览，绝不缩放窗口。
  void _setScaleFromPanel(double v) {
    final wanted = v.clamp(0.35, _maxPetScale).toDouble();
    Config.instance.setScale(wanted);
    final r = rig;
    if (r != null) engine.scale = kBasePetWidth / r.canvasW * wanted;
    setState(() {});
  }

  /// 唯一的尺寸入口：先写配置，再做一次窗口重排。
  /// 重入保护 + 末位优先：滑杆连续触发时同一时刻只有一次 resize 在跑，
  /// 且以最后一个值为准（旧实现会重入并叠加 2-3 次 setSize/setPosition）。
  Future<void> _applyScale(double petScale) async {
    final wanted = petScale.clamp(0.35, _maxPetScale).toDouble();
    Config.instance.setScale(wanted);
    _pendingScale = wanted;
    if (_applyingScale) return;
    _applyingScale = true;
    try {
      while (_pendingScale != null) {
        final target = _pendingScale!;
        _pendingScale = null;
        await _resizeNow(target);
      }
    } finally {
      _applyingScale = false;
    }
  }

  Future<void> _resizeNow(double petScale) async {
    Trace.log('resizeNow enter $petScale');
    final r = rig;
    if (r == null) return;
    final s = kBasePetWidth / r.canvasW * petScale;
    engine.scale = s;
    engine.windowW = r.canvasW * s + kSidePad * 2;
    engine.windowH = r.canvasH * s + kBubbleSpace;
    await WindowsWindowService.instance.resizeToPet(petScale);
    await Config.instance.applyToPlatform();
    if (mounted) setState(() {});
  }

  void _toggleClickThrough() {
    final cfg = Config.instance;
    cfg.setClickThrough(!cfg.clickThrough);
    cfg.applyToPlatform();
    _pushHitTestRegions();
    setState(() {});
  }

  /// Tell the C++ layer which pixels are the pet and the toggle button.
  /// In click-through mode only the button stays clickable.
  void _pushHitTestRegions() {
    final r = rig;
    if (r == null) return;
    final petW = r.canvasW * engine.scale;
    final petH = r.canvasH * engine.scale;
    final winW = petW + kSidePad * 2;
    final petRect = Rect.fromLTWH(kSidePad, kBubbleSpace, petW, petH);
    final bandOn = engine.bubbleText != null;
    WindowsWindowService.instance.setHitTestRegions(
      pet: petRect,
      button: _buttonRect(petW, petH),
      band: bandOn ? Rect.fromLTWH(0, 0, winW, kBubbleSpace) : Rect.zero,
      bandOn: bandOn,
      fullPassthrough: Config.instance.clickThrough,
    );
  }

  bool _bubbleShown = false;

  /// 气泡出现/消失时补推一次窗口区域：气泡带不在区域内会被 SetWindowRgn 裁掉。
  void _syncBubbleBand(bool visible) {
    if (visible == _bubbleShown) return;
    _bubbleShown = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !WindowsWindowService.instance.panelMode) {
        _pushHitTestRegions();
      }
    });
  }

  /// 小眼睛按钮在窗口内的位置：头部图层右上角外侧 kButtonGap 像素处，
  /// 再夹回窗口内（小尺寸时头部右缘可能超出窗口宽度）。
  Rect _buttonRect(double petW, double petH) {
    final winW = petW + kSidePad * 2;
    final winH = petH + kBubbleSpace;
    final r = rig;
    final s = engine.scale;
    double right;
    double top;
    if (r == null) {
      right = winW;
      top = kBubbleSpace;
    } else {
      final head = r.layers.firstWhere((l) => l.name == 'head',
          orElse: () => r.layers.isEmpty
              ? const RigLayer(name: 'head', crop: Rect.zero, zOrder: 0)
              : r.layers.last);
      // headTopRight 量的是头部图层"真实内容"右上角（裁剪框右缘多为空白）
      final anchor =
          r.anchor('headTopRight') ?? Offset(head.crop.right, head.crop.top);
      right = kSidePad + anchor.dx * s;
      top = kBubbleSpace + anchor.dy * s;
    }
    final left =
        (right + kButtonGapX).clamp(2.0, winW - kButtonSize - 2).toDouble();
    final t = (top - kButtonSize - kButtonGapY)
        .clamp(2.0, winH - kButtonSize - 2)
        .toDouble();
    return Rect.fromLTWH(left, t, kButtonSize, kButtonSize);
  }

  /// Native HTCAPTION drag loop: the compositor moves the window in
  /// lockstep with the cursor - no per-frame SetWindowPos, no ghosting.
  Future<void> _onDragStart(DragStartDetails d) async {
    engine.beginNativeDrag();
    try {
      await windowManager.startDragging();
    } finally {
      final p = await windowManager.getPosition();
      engine.endNativeDrag(p, gravityFall: Config.instance.gravityFall);
    }
  }

  /// Eye midpoint in screen logical px (window origin + local offset).
  Offset? _eyeAnchorScreen() {
    final r = rig;
    if (r == null) return null;
    final eyeL = r.anchor('eyeL');
    final eyeR = r.anchor('eyeR');
    if (eyeL == null || eyeR == null) return null;
    final s = engine.scale;
    final local = Offset(
      kSidePad + (eyeL.dx + eyeR.dx) / 2 * s,
      kBubbleSpace + (eyeL.dy + eyeR.dy) / 2 * s,
    );
    return engine.windowPos + local;
  }

  void _onTap(TapUpDetails d) {
    // 手势挂在 Positioned(kSidePad, kBubbleSpace) 上，localPosition 已经是
    // 宠物画布坐标系的像素值 —— 不能再减内边距（历史 bug：命中区整体偏移
    // 约 (20, 245) 画布像素，导致点尾巴落进身体区、只能听到下半身音效）。
    final region = engine.hitRegion(d.localPosition);
    if (region != PetRegion.none) engine.react(region);
  }

  @override
  Widget build(BuildContext context) {
    final r = rig;
    if (r == null) return const SizedBox.shrink();

    final petW = r.canvasW * engine.scale;
    final petH = r.canvasH * engine.scale;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _panelOpen
            ? SettingsPanel(
                key: const ValueKey('panel'),
                rig: r,
                engine: engine,
                onClose: _closeSettings,
                onScaleChanged: _setScaleFromPanel,
                onApplied: _applyConfigChange,
                maxScale: _maxPetScale,
              )
            : KeyedSubtree(
                key: const ValueKey('pet'),
                child: AnimatedBuilder(
                  animation: Listenable.merge([engine, Config.instance]),
                  builder: (context, _) => _petStack(r, petW, petH),
                ),
              ),
      ),
    );
  }

  Widget _petStack(RigData r, double petW, double petH) {
    final buttonRect = _buttonRect(petW, petH);
    // 气泡贴着"头部真实内容顶部"：原来钉在窗口顶部，放大后窗口占满工作区，
    // 气泡就飘到屏幕顶端了。用 bottom 定位，气泡高度变化也不会跑偏。
    final headTop = r.anchor('headTopCenter')?.dy ?? r.canvasH * 0.235;
    final bubbleBottom = (petH - headTop * engine.scale + 8)
        .clamp(0.0, petH + kBubbleSpace - 40)
        .toDouble();
    final bubbleText = engine.bubbleText;
    _syncBubbleBand(bubbleText != null);
    final shown = bubbleText == null
        ? ''
        : bubbleText.substring(
            0,
            engine.bubbleChars.clamp(1, bubbleText.length).floor(),
          );
    return SizedBox(
      width: petW + kSidePad * 2,
      height: petH + kBubbleSpace,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: kSidePad,
            top: kBubbleSpace,
            width: petW,
            height: petH,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: _onTap,
              onPanStart: _onDragStart,
              child: PetRigView(
                  rig: r, pose: engine.pose(), scale: engine.scale),
            ),
          ),
          Positioned(
            left: kSidePad,
            top: kBubbleSpace,
            width: petW,
            height: petH,
            child: IgnorePointer(
              child: BongoPaws(
                leftT: engine.bongoLeftT,
                rightT: engine.bongoRightT,
                width: petW,
                height: petH,
              ),
            ),
          ),
          // 穿透开关（小眼睛）：紧贴桌宠头部右上角；穿透态下 C++ 仍保留该矩形可点
          Positioned(
            left: buttonRect.left,
            top: buttonRect.top,
            child: _ThroughButton(onToggle: _toggleClickThrough),
          ),
          if (bubbleText != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: bubbleBottom,
              child: Center(child: SpeechBubble(text: shown)),
            ),
          if (Config.instance.dialogue) _IdleBubbleTicker(engine: engine),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _topGuard?.cancel();
    windowManager.removeListener(this);
    poller.stop();
    engine.dispose();
    super.dispose();
  }
}

/// Calls engine.maybeIdleBubble() once a second (no rebuild of its own).
class _IdleBubbleTicker extends StatefulWidget {
  const _IdleBubbleTicker({required this.engine});

  final PetEngine engine;

  @override
  State<_IdleBubbleTicker> createState() => _IdleBubbleTickerState();
}

class _IdleBubbleTickerState extends State<_IdleBubbleTicker> {
  @override
  void initState() {
    super.initState();
    Stream.periodic(const Duration(seconds: 1)).listen((_) {
      widget.engine.maybeIdleBubble();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Small round button on the pet that toggles click-through mode.
class _ThroughButton extends StatelessWidget {
  const _ThroughButton({required this.onToggle});

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cfg = Config.instance;
    return Tooltip(
      message: cfg.clickThrough
          ? '穿透已开启（再次点击本按钮恢复）'
          : '鼠标穿透开关',
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0x66000000),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: cfg.clickThrough ? const Color(0xFFFF8AB5) : Colors.white38,
              width: 1,
            ),
          ),
          child: Icon(
            cfg.clickThrough ? Icons.visibility_off : Icons.visibility,
            size: 16,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// Android floating-window pet. The overlay window itself is dragged by the
/// system (flutter_overlay_window enableDrag); touches feed the gaze tracker
/// and the same rig renders at the configured scale.
class AndroidOverlayPet extends StatefulWidget {
  const AndroidOverlayPet({super.key});

  @override
  State<AndroidOverlayPet> createState() => _AndroidOverlayPetState();
}

class _AndroidOverlayPetState extends State<AndroidOverlayPet> {
  final PetEngine engine = PetEngine();
  RigData? rig;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Config.instance.load();
    final r = await RigData.load(readAsset: rootBundle.loadString);
    rig = r;
    engine.rig = r;
    engine.scale = kBasePetWidth / r.canvasW * Config.instance.petScale;
    await AudioService.instance.preload();
    OverlayService.listenSettings((msg) {
      if (msg['cmd'] == 'scale') {
        setState(() => engine.scale =
            kBasePetWidth / r.canvasW * (msg['v'] as num).toDouble());
      }
    });
    engine.start();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final r = rig;
    if (r == null) return const SizedBox.shrink();
    final petW = r.canvasW * engine.scale;
    final petH = r.canvasH * engine.scale;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: engine,
        builder: (context, _) {
          final eyeL = r.anchor('eyeL');
          final eyeR = r.anchor('eyeR');
          final eyeLocal = (eyeL != null && eyeR != null)
              ? Offset(
                  (eyeL.dx + eyeR.dx) / 2 * engine.scale,
                  (eyeL.dy + eyeR.dy) / 2 * engine.scale,
                )
              : null;
          final bubbleText = engine.bubbleText;
          final shown = bubbleText == null
              ? ''
              : bubbleText.substring(
                  0, engine.bubbleChars.clamp(1, bubbleText.length).floor());
          return SizedBox(
            width: petW,
            height: petH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Listener(
                  onPointerDown: (e) {
                    if (eyeLocal != null) {
                      engine.feedPointerLocal(
                          e.localPosition, eyeLocal, 300 * engine.scale);
                    }
                  },
                  onPointerMove: (e) {
                    if (eyeLocal != null) {
                      engine.feedPointerLocal(
                          e.localPosition, eyeLocal, 300 * engine.scale);
                    }
                  },
                  onPointerUp: (_) => engine.markIdle(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: (d) {
                      final region = engine.hitRegion(d.localPosition);
                      if (region != PetRegion.none) engine.react(region);
                    },
                    child: PetRigView(
                        rig: r, pose: engine.pose(), scale: engine.scale),
                  ),
                ),
                if (bubbleText != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: petH + 8,
                    child: Center(child: SpeechBubble(text: shown)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    engine.dispose();
    super.dispose();
  }
}

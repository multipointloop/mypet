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
import 'package:desktop_multi_window/desktop_multi_window.dart';
import '../../core/trace.dart';
import '../../main.dart' show openSettingsWindow;

/// Layout constants (logical px at petScale = 1.0).
const double kBasePetWidth = 260;
const double kBubbleSpace = 120;
const double kSidePad = 10;

/// Windows: transparent always-on-top pet window.
class WindowsPetHome extends StatefulWidget {
  const WindowsPetHome({super.key});

  @override
  State<WindowsPetHome> createState() => _WindowsPetHomeState();
}

class _WindowsPetHomeState extends State<WindowsPetHome> {
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
    await _applyScale(cfg.petScale);
    _pushHitTestRegions();

    // the independent settings window saves prefs in its own engine and
    // pings us (configChanged -> reload) - re-apply geometry/regions here
    Config.instance.addListener(_onConfigChangedExternally);
    _lastAppliedScale = cfg.petScale;

    win.onScaleDelta = (delta) =>
        _applyScale((cfg.petScale + delta).clamp(0.35, 2.5));
    win.onToggleClickThrough = () => _toggleClickThrough();
    win.onToggleBongo = () {
      cfg.setBongoHook(!cfg.bongoHook);
      cfg.applyToPlatform();
      setState(() {});
    };
    win.onToggleSettings = () => openSettingsWindow();
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
        _applyScale((cfg.petScale + 0.1).clamp(0.35, 2.5));
      } else if (id == 1) {
        _applyScale((cfg.petScale - 0.1).clamp(0.35, 2.5));
      } else if (id == 3) {
        openSettingsWindow();
      } else if (id == 2) {
        // Ctrl+Alt+T: click-through toggle (also the way OUT, since in
        // passthrough mode only the on-pet button stays clickable)
        _toggleClickThrough();
      }
    };
    await NativeChannel.instance.start();

    poller.onCursor = (logicalPos) {
      final eye = _eyeAnchorScreen();
      if (eye != null) engine.feedPointer(logicalPos, eye, 360 * engine.scale);
    };
    await poller.start();

    engine.start();
    if (mounted) setState(() {});

    // TEMP crash repro: auto-open the settings window 4s after boot
    assert(() {
      Timer(const Duration(seconds: 4), () async {
        debugPrint('[repro] opening settings window...');
        try {
          await openSettingsWindow();
          debugPrint('[repro] settings window opened OK');
        } catch (e) {
          debugPrint('[repro] openSettingsWindow threw: $e');
        }
      });
      return true;
    }());
  }

  double _lastAppliedScale = 0;

  /// Config listener on the pet engine: the settings window lives in a
  /// separate engine and only writes prefs, so geometry must be re-applied
  /// here whenever the saved values change.
  void _onConfigChangedExternally() {
    Trace.log('onConfigChangedExternally enter');
    final cfg = Config.instance;
    if ((cfg.petScale - _lastAppliedScale).abs() > 0.0001) {
      _lastAppliedScale = cfg.petScale;
      _applyScale(cfg.petScale); // includes applyToPlatform (pet engine!)
    } else {
      _pushHitTestRegions();
      cfg.applyToPlatform(); // bongo/autostart/click-through, same engine
    }
    setState(() {});
  }

  Future<void> _applyScale(double petScale) async {
    Trace.log('applyScale enter $petScale');
    final r = rig;
    if (r == null) return;
    Config.instance.setScale(petScale);
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
    // button widget sits at Positioned(right:2, top:2), 30x30
    WindowsWindowService.instance.setHitTestRegions(
      pet: petRect,
      button: Rect.fromLTWH(winW - 32, 2, 30, 30),
      fullPassthrough: Config.instance.clickThrough,
    );
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
    final canvasPoint = Offset(
        d.localPosition.dx - kSidePad, d.localPosition.dy - kBubbleSpace);
    final region = engine.hitRegion(canvasPoint);
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
      body: AnimatedBuilder(
        animation: Listenable.merge([engine, Config.instance]),
        builder: (context, _) {
          final bubbleText = engine.bubbleText;
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
                // click-through toggle (top-right corner of the window):
                // it stays clickable even in passthrough mode (C++ hit-test
                // keeps this rect alive)
                Positioned(
                  right: 2,
                  top: 2,
                  child: _ThroughButton(onToggle: _toggleClickThrough),
                ),
                if (bubbleText != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: Center(child: SpeechBubble(text: shown)),
                  ),
                if (Config.instance.dialogue) _IdleBubbleTicker(engine: engine),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
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
      // pick up settings changed in the independent settings window
      Config.instance.syncIfChanged();
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

    // TEMP crash repro (debug only): open the settings window then spam
    // configChanged like a slider drag would
    assert(() {
      Timer(const Duration(seconds: 5), () async {
        debugPrint('[repro] opening settings window...');
        try {
          await openSettingsWindow();
          debugPrint('[repro] opened OK');
        } catch (e) {
          debugPrint('[repro] open FAILED: $e');
          return;
        }
        await Future.delayed(const Duration(seconds: 2));
        for (var i = 0; i < 15; i++) {
          try {
            await DesktopMultiWindow.invokeMethod(0, 'configChanged');
            debugPrint('[repro] ping $i ok');
          } catch (e) {
            debugPrint('[repro] ping $i FAILED: $e');
          }
          await Future.delayed(const Duration(milliseconds: 60));
        }
        debugPrint('[repro] sequence complete, still alive');
      });
      return true;
    }());
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

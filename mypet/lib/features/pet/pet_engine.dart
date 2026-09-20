import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/audio_service.dart';
import '../../core/config.dart';
import '../../core/rig_model.dart';
import '../../core/trace.dart';
import '../../core/rig_view.dart' show PetPose;
import 'dialogue_lines.dart' show pickLine;

enum PetRegion { head, body, tail, legs, none }

/// 裙子以下的"跳一跳"式折叠：蓄力 3s -> 弹回 1s（带轻微过冲）
enum FoldPhase { idle, charging, springing }

enum PetMood { normal, happy, sleepy }

/// The pet's brain: gaze smoothing, blink scheduling, click reactions,
/// idle dialogue and (Windows) gravity physics. Driven by a Ticker.
class PetEngine with ChangeNotifier {
  RigData? rig;

  /// rig px -> logical px, computed from AppConfig.petScale
  double scale = 1;

  // ---- gaze ----
  Offset gazeTarget = Offset.zero;
  Offset gaze = Offset.zero;
  DateTime _lastPointerMove = DateTime.now();

  // ---- blink ----
  double blink = 0; // 0 open, 1..0..1 curve progress drives pose
  bool _blinkAnimating = false;
  DateTime _nextBlinkAt = DateTime.now();

  // ---- reactions ----
  double jumpY = 0; // rig px
  double _jumpVel = 0;
  double tailWag = 0;
  double _wagT = 0; // >0 = wagging, seconds remaining
  double squash = 0;
  double _squashT = 0;
  double exprEyeScaleY = 1.0;
  double _exprT = 0;
  final math.Random _rng = math.Random();

  // ---- mood / sleep ----
  PetMood mood = PetMood.normal;
  Duration _idleFor = Duration.zero;

  // ---- dialogue ----
  String? bubbleText;
  double get bubbleChars => _bubbleCharsShown;
  double _bubbleCharsShown = 0;
  DateTime? _bubbleHideAt;
  DateTime _nextIdleBubbleAt = DateTime.now();
  final math.Random _lineRng = math.Random();

  /// 取台词：优先用户自定义（设置面板可编辑），否则内置默认。
  String _line(String key) =>
      pickLine(key, _lineRng, Config.instance.dialogueLines);

  // ---- physics (Windows drag & fall) ----
  bool physicsActive = false;
  bool dragActive = false; // native OS drag loop in progress (freeze gaze)
  Offset windowPos = Offset.zero; // logical screen px
  Offset windowVel = Offset.zero;
  double windowW = 300, windowH = 460;
  double groundY = 1048576.0; // logical px：地面线 = 工作区底边；落地时 windowPos.dy = groundY - windowH
  double devicePixelRatio = 1;

  /// Platform bridge: applied once per tick when the window must move
  /// (drag or fall) - keeps SetWindowPos off the pointer-event flood.
  void Function(Offset logicalPos)? onWindowMoveRequested;

  // bongo cat
  double bongoLeftT = 0, bongoRightT = 0;

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  void start() {
    _ticker ??= Ticker(_onTick);
    _ticker!.start();
    _scheduleNextBlink();
    _scheduleIdleBubble();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  // ================= tick =================
  void _onTick(Duration now) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;
    final d = dt.clamp(0.001, 0.1);

    // -- gaze smoothing: exponential lerp, k = rig.smoothing per second
    final k = rig?.smoothing ?? 12;
    final idle = DateTime.now().difference(_lastPointerMove).inMilliseconds > 3000;
    final target = idle ? Offset.zero : gazeTarget;
    final f = 1 - math.exp(-k * d);
    gaze = Offset(
      gaze.dx + (target.dx - gaze.dx) * f,
      gaze.dy + (target.dy - gaze.dy) * f,
    );

    // -- blink
    if (!_blinkAnimating && DateTime.now().isAfter(_nextBlinkAt)) {
      _blinkAnimating = true;
      blink = 0;
    }
    if (_blinkAnimating) {
      blink += d / 0.16; // 160 ms per full close-open
      if (blink >= 1) {
        blink = 0;
        _blinkAnimating = false;
        _scheduleNextBlink();
      }
    }

    // -- jump physics (reaction hop)
    if (_jumpVel != 0 || jumpY > 0) {
      _jumpVel -= (rig?.gravity ?? 2000) * 1.6 * d;
      jumpY += _jumpVel * d;
      if (jumpY <= 0) {
        jumpY = 0;
        _jumpVel = 0;
      }
    }

    // -- tail wag: damped sine, 5 Hz
    if (_wagT > 0) {
      _wagT -= d;
      tailWag = 0.21 *
          math.sin(_wagT * 2 * math.pi * 5) *
          math.exp(-(5 - _wagT).abs() * 0.8);
      if (_wagT <= 0) tailWag = 0;
    }

    // -- squash (landing / patted body)
    if (_squashT > 0) {
      _squashT -= d;
      squash = math.sin((1 - _squashT / 0.35) * math.pi) * 0.9;
      if (_squashT <= 0) squash = 0;
    }

    // -- 裙子以下的跳一跳折叠
    advanceFold(d);

    // -- surprised eyes
    if (_exprT > 0) {
      _exprT -= d;
      exprEyeScaleY = 1 + 0.35 * math.sin((_exprT / 0.5) * math.pi);
      if (_exprT <= 0) exprEyeScaleY = 1;
    }

    // -- mood & idle
    if (idle) {
      _idleFor += Duration(milliseconds: (d * 1000).round());
    } else {
      _idleFor = Duration.zero;
      if (mood == PetMood.sleepy) mood = PetMood.normal;
    }
    if (_idleFor > const Duration(seconds: 90) && mood != PetMood.sleepy) {
      mood = PetMood.sleepy;
      showBubble(_line('sleep'));
    }

    // -- dialogue typewriter & hide
    if (bubbleText != null) {
      _bubbleCharsShown = math.min(bubbleText!.length.toDouble(),
          _bubbleCharsShown + d * 22); // ~22 chars/s
      if (_bubbleHideAt != null && DateTime.now().isAfter(_bubbleHideAt!)) {
        bubbleText = null;
        _bubbleHideAt = null;
        _scheduleIdleBubble();
      }
    }

    // -- breathing
    // (derived in pose from a wall-clock phase, no stored state)

    // -- window physics (gravity fall; the drag itself is the native
    // HTCAPTION loop, which moves the window without any Dart involvement)
    if (!dragActive && physicsActive) {
      _stepPhysics(d);
    }

    // -- bongo paw decay
    bongoLeftT = (bongoLeftT - d).clamp(0.0, 1.0);
    bongoRightT = (bongoRightT - d).clamp(0.0, 1.0);

    notifyListeners();
  }

  PetPose pose() {
    final phase = DateTime.now().millisecondsSinceEpoch / 1000;
    final breathing = mood == PetMood.sleepy ? 0.5 : 1.0;
    // while dragging / falling the puppet is rigid: no gaze-driven offsets
    final gazeFrozen = dragActive || physicsActive;
    // window_manager.setOpacity is unreliable on DWM-composited acrylic
    // windows, so passthrough ghosting is applied to the CONTENT instead
    final baseOpacity = Config.instance.clickThrough
        ? Config.instance.clickThroughOpacity
        : Config.instance.normalOpacity;
    return PetPose(
      gaze: gazeFrozen ? Offset.zero : gaze,
      blink: mood == PetMood.sleepy ? 0.55 : blink, // half-closed when sleepy
      exprEyeScaleY: exprEyeScaleY,
      tailWag: tailWag,
      jumpY: jumpY,
      squash: squash,
      fold: fold,
      breathe: math.sin(phase * 2 * math.pi / 3.2) * breathing,
      opacity: baseOpacity * (mood == PetMood.sleepy ? 0.96 : 1.0),
    );
  }

  // ================= input =================

  /// Feed a screen-space pointer position (logical px) - Windows cursor
  /// poller or Android touch. [eyeAnchorScreen] is the midpoint between the
  /// two eye anchors in the same coordinate space.
  void feedPointer(Offset screenPoint, Offset eyeAnchorScreen, double radius) {
    if (dragActive) return; // dragging: keep gaze frozen, no neck jitter
    final now = DateTime.now();
    if ((screenPoint - _lastRaw).distance >= 1.0) {
      _lastPointerMove = now;
    }
    _lastRaw = screenPoint;
    final v = (screenPoint - eyeAnchorScreen) / radius;
    final len = v.distance;
    gazeTarget = len > 1 ? v / len : v;
  }

  Offset _lastRaw = Offset.zero;

  /// Feed a pointer in window-local coordinates (Android overlay window).
  void feedPointerLocal(Offset local, Offset eyeAnchorLocal, double radius) {
    feedPointer(local, eyeAnchorLocal, radius);
  }

  void markIdle() => _lastPointerMove =
      DateTime.now().subtract(const Duration(seconds: 10));

  // ================= interaction =================

  PetRegion hitRegion(Offset canvasPoint) {
    final r = rig;
    if (r == null) return PetRegion.none;
    // canvasPoint is in pet-widget coordinates (top-left origin, scaled);
    // rig.json uses the same convention, just unscaled
    final rigPoint = Offset(canvasPoint.dx / scale, canvasPoint.dy / scale);
    PetRegion? best;
    for (final entry in r.regions.entries) {
      if (entry.value.contains(rigPoint)) {
        best = switch (entry.key) {
          'head' => PetRegion.head,
          'tail' => PetRegion.tail,
        'legs' => PetRegion.legs,
          'body' => PetRegion.body,
          _ => null,
        };
      }
    }
    return best ?? PetRegion.none;
  }

  void react(PetRegion region) {
    switch (region) {
      case PetRegion.head:
        AudioService.instance.play('bounce');
        _jumpVel = 320; // hop!
        _exprT = 0.5; // wide eyes
        _wagT = 1.2; // happy tail
        if (Config.instance.dialogue && _rng.nextBool()) {
          showBubble(_line('head'));
        }
      case PetRegion.body:
        AudioService.instance.play('click_body');
        _squashT = 0.35;
        if (Config.instance.dialogue && _rng.nextDouble() < 0.4) {
          showBubble(_line('body'));
        }
      case PetRegion.tail:
        AudioService.instance.play('click_tail');
        _wagT = 2.0;
        if (Config.instance.dialogue && _rng.nextDouble() < 0.3) {
          showBubble(_line('tail'));
        }
      case PetRegion.legs:
        startFold();
      case PetRegion.none:
        break;
    }
    notifyListeners();
  }

  // ---- 裙子以下：跳一跳式折叠 ----

  FoldPhase foldPhase = FoldPhase.idle;
  double _foldT = 0;
  static const double foldChargeSecs = 3.0;
  static const double foldSpringSecs = 1.0;

  /// 折叠进度：蓄力 0->1，弹回 1->0（easeOutBack 过冲出负值 = 轻微拉伸）
  double get fold {
    switch (foldPhase) {
      case FoldPhase.idle:
        return 0;
      case FoldPhase.charging:
        final t = (_foldT / foldChargeSecs).clamp(0.0, 1.0);
        return t * t * (3 - 2 * t);
      case FoldPhase.springing:
        final t = (_foldT / foldSpringSecs).clamp(0.0, 1.0);
        const c1 = 1.70158;
        const c3 = c1 + 1;
        final u = t - 1;
        return 1 - (1 + c3 * u * u * u + c1 * u * u);
    }
  }

  void startFold() {
    if (foldPhase != FoldPhase.idle) return;
    foldPhase = FoldPhase.charging;
    _foldT = 0;
    Trace.log('fold start');
    AudioService.instance.play('charge');
    notifyListeners();
  }

  /// 由 tick 驱动；也可在测试里直接喂 dt。
  void advanceFold(double d) {
    if (foldPhase == FoldPhase.idle) return;
    _foldT += d;
    if (foldPhase == FoldPhase.charging && _foldT >= foldChargeSecs) {
      _foldT = 0;
      foldPhase = FoldPhase.springing;
      Trace.log('fold spring');
      AudioService.instance.play('swoosh');
    } else if (foldPhase == FoldPhase.springing &&
        _foldT >= foldSpringSecs) {
      _foldT = 0;
      foldPhase = FoldPhase.idle;
      Trace.log('fold done');
    }
  }

  // ---- bongo cat ----
  void bongoTap({required bool left}) {
    if (left) {
      bongoLeftT = 0.18;
    } else {
      bongoRightT = 0.18;
    }
    AudioService.instance.play('key');
  }

  // ---- dialogue ----
  void showBubble(String text, {bool idle = false}) {
    if (!Config.instance.dialogue && idle) return;
    bubbleText = text;
    _bubbleCharsShown = 0;
    _bubbleHideAt = DateTime.now().add(const Duration(seconds: 4));
    notifyListeners();
  }

  void _scheduleIdleBubble() {
    final range = _rng.nextInt(26) + 20; // 20..45 s
    _nextIdleBubbleAt = DateTime.now().add(Duration(seconds: range));
  }

  void maybeIdleBubble() {
    if (bubbleText != null) return;
    if (DateTime.now().isAfter(_nextIdleBubbleAt)) {
      showBubble(_line('idle'), idle: true);
      _scheduleIdleBubble();
    }
  }

  void _scheduleNextBlink() {
    if (!Config.instance.idleBlink) return;
    _nextBlinkAt = DateTime.now().add(
      Duration(milliseconds: 1200 + _rng.nextInt(2000)),
    );
  }

  // ================= physics (Windows) =================

  void startFall() {
    physicsActive = true;
    Trace.log('physics start y=${windowPos.dy.toStringAsFixed(0)} groundY=${groundY.toStringAsFixed(0)} winH=${windowH.toStringAsFixed(0)}');
  }


  /// Native HTCAPTION drag loop: the compositor moves the window in
  /// lockstep with the cursor - no per-frame SetWindowPos, no ghosting.
  /// [endNativeDrag] resyncs the position and optionally applies gravity.
  void beginNativeDrag() {
    dragActive = true;
    physicsActive = false;
    windowVel = Offset.zero;
    notifyListeners();
  }

  void endNativeDrag(Offset newPos, {required bool gravityFall}) {
    dragActive = false;
    windowPos = newPos;
    if (gravityFall) {
      startFall();
    }
    notifyListeners();
  }

  void _stepPhysics(double d) {
    final g = rig?.gravity ?? 2000;
    windowVel += Offset(0, g * d);
    windowPos += windowVel * d;

    final bottom = windowPos.dy + windowH;
    if (bottom >= groundY) {
      windowPos = Offset(windowPos.dx, groundY - windowH);
      final impact = windowVel.dy;
      windowVel = Offset(windowVel.dx * 0.55, -impact * (rig?.bounce ?? 0.35));
      if (impact > 250) {
        AudioService.instance.play('land');
        _squashT = 0.35;
      }
      if (windowVel.dy.abs() < 60) {
        windowVel = Offset(windowVel.dx * 0.8, 0);
        if (windowVel.dx.abs() < 15) {
          physicsActive = false;
          windowVel = Offset.zero;
          Trace.log('physics settle y=${windowPos.dy.toStringAsFixed(0)}');
        }
      }
    }
    onWindowMoveRequested?.call(windowPos);
    notifyListeners();
  }
}

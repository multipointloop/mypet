import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'rig_model.dart';

/// One frame of animation state for the layered rig.
class PetPose {
  const PetPose({
    this.gaze = Offset.zero, // smoothed unit-disk offset (dx, dy) in [-1, 1]
    this.blink = 0, // 0 = open; 0..1 closes (sin curve applied)
    this.exprEyeScaleY = 1.0, // surprise wide-eye factor
    this.headExtra = Offset.zero, // reaction head nudge
    this.tailWag = 0, // radians, damped oscillation
    this.jumpY = 0, // rig px, positive = up
    this.squash = 0, // 0 none .. 1 full squash (landing)
    this.fold = 0, // 裙子以下跳一跳折叠；负值 = 弹回时的轻微拉伸
    this.breathe = 0, // -1..1 breathing phase
    this.opacity = 1.0,
  });

  final Offset gaze;
  final double blink;
  final double exprEyeScaleY;
  final Offset headExtra;
  final double tailWag;
  final double jumpY;
  final double squash;
  final double fold;
  final double breathe;
  final double opacity;
}

double _sin01(double t) =>
    0.5 - 0.5 * math.cos(2 * math.pi * t.clamp(0.0, 1.0));

/// Renders the sliced layers with per-layer motion.
///
/// Coordinate system: rig canvas pixels * [scale]; the canvas bottom edge sits
/// at the widget bottom (feet on the ground), horizontally centered.
class PetRigView extends StatelessWidget {
  const PetRigView({
    super.key,
    required this.rig,
    required this.pose,
    required this.scale,
  });

  final RigData rig;
  final PetPose pose;
  final double scale;

  Size get petSize => Size(rig.canvasW * scale, rig.canvasH * scale);

  Offset? _anchorIn(RigLayer layer, String anchorName) {
    final a = rig.anchor(anchorName);
    if (a == null) return null;
    return Offset((a.dx - layer.crop.left) * scale, (a.dy - layer.crop.top) * scale);
  }

  @override
  Widget build(BuildContext context) {
    // Breathing & landing squash apply to the WHOLE rig from the feet pivot,
    // so every layer (head included) moves in lockstep - the neck seam can
    // never open. Gaze-driven motion stays per-layer inside.
    final breathe = 1 + pose.breathe * 0.015; // ±1.5% height
    // squash = 点下半身的短促挤压；fold = 裙子以下的蓄力折叠。
    // fold 幅度（17%/14%）比 squash 稍大但不过度；负值即 Q 弹过冲。
    final squashY =
        (1 - pose.squash * 0.12) * (1 - pose.fold * 0.17) * breathe;
    final squashX =
        (1 + pose.squash * 0.10) * (1 + pose.fold * 0.14) / breathe;

    final children = <Widget>[];
    final headPivot = rig.anchor('headPivot') ?? const Offset(512, 640);

    for (final layer in rig.layers) {
      final w = layer.crop.width * scale;
      final h = layer.crop.height * scale;
      final left = layer.crop.left * scale;
      // widget top-left == rig canvas top-left (same convention as rig.json),
      // so a layer simply sits at its crop offset
      final top = layer.crop.top * scale;

      Widget img = Image.asset(
        layer.asset,
        width: w,
        height: h,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        opacity: AlwaysStoppedAnimation<double>(pose.opacity),
      );

      // --- inner motion for the eyes: pupil slide + blink. Closing fades
      // the artwork eyes out and fades a horizontal closed-eye line in at
      // one shared level (both lids stay level); the line softens on the
      // eye that sits behind the bangs. ---
      if (layer.name == 'eyeL' || layer.name == 'eyeR') {
        final pupilShift =
            Offset(pose.gaze.dx * rig.pupilMaxX, pose.gaze.dy * rig.pupilMaxY) *
                scale;
        img = Transform.translate(offset: pupilShift, child: img);

        final blink01 = _sin01(pose.blink);
        if (blink01 > 0) {
          final isLeft = layer.name == 'eyeL';
          // 左眼在原画里被刘海遮挡：闭合线做淡化处理
          final lineAlpha = (isLeft ? 0.55 : 1.0) * blink01;
          final eyeAnchor = rig.anchor(layer.name) ?? layer.crop.center;
          final other = rig.anchor(layer.name == 'eyeL' ? 'eyeR' : 'eyeL') ??
              eyeAnchor;
          final sharedY = (eyeAnchor.dy + other.dy) / 2;
          final ax = (eyeAnchor.dx - layer.crop.left) * scale;
          final ay = (sharedY - layer.crop.top) * scale;
          final lineW = w * 0.78;
          final lineH = math.max(1.4 * scale, h * 0.075);
          img = Stack(
            clipBehavior: Clip.none,
            children: [
              Opacity(opacity: 1 - blink01, child: img),
              Positioned(
                left: ax - lineW / 2 + pupilShift.dx * 0.5,
                top: ay - lineH / 2 + pupilShift.dy * 0.5,
                child: Opacity(
                  opacity: lineAlpha,
                  child: Container(
                    width: lineW,
                    height: lineH,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7A5A63),
                      borderRadius: BorderRadius.circular(lineH),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      }

      // --- head motion: the head AND the eyes ride the same transform, so
      // the gaze tilt can never detach the eyes from the face. The head crop
      // extends under the collar and the body draws above it, therefore no
      // seam can open on either side. ---
      if (layer.name == 'head' || layer.name == 'eyeL' || layer.name == 'eyeR') {
        final pivot = Offset(
            (headPivot.dx - layer.crop.left) * scale,
            (headPivot.dy - layer.crop.top) * scale);
        final shift = (Offset(pose.gaze.dx * rig.headShiftX,
                    pose.gaze.dy * rig.headShiftY) +
                pose.headExtra) *
            scale;
        final rotation = pose.gaze.dx * rig.headRotDeg * math.pi / 180;
        img = Transform(
          transform: Matrix4.identity()
            ..translateByDouble(pivot.dx, pivot.dy, 0, 1)
            ..rotateZ(rotation)
            ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1),
          child: Transform.translate(offset: shift, child: img),
        );
      }

      // --- tail wag around the tail root ---
      if (layer.name == 'tail') {
        final pivot = _anchorIn(layer, 'tailPivot') ?? Offset(w * 0.2, h * 0.5);
        img = Transform(
          transform: Matrix4.identity()
            ..translateByDouble(pivot.dx, pivot.dy, 0, 1)
            ..rotateZ(pose.tailWag)
            ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1),
          child: img,
        );
      }

      children.add(Positioned(left: left, top: top, child: img));
    }

    return SizedBox(
      width: petSize.width,
      height: petSize.height,
      child: Transform(
        transform: Matrix4.identity()
          ..translateByDouble(petSize.width / 2, petSize.height, 0, 1)
          ..scaleByDouble(squashX, squashY, 1, 1)
          ..translateByDouble(-petSize.width / 2, -petSize.height, 0, 1),
        child: Transform.translate(
          offset: Offset(0, -pose.jumpY * scale),
          child: Stack(clipBehavior: Clip.none, children: children),
        ),
      ),
    );
  }
}

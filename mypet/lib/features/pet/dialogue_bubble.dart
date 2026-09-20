import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Soft pink speech bubble with a little tail, drawn to sit above the head.
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({super.key, required this.text, this.maxWidth = 220});

  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _BubblePainter(),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(242),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFB7CD), width: 1.6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(36),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.35,
            color: Color(0xFF5A4A52),
            fontWeight: FontWeight.w500,
            fontFamily: 'Microsoft YaHei UI',
            fontFamilyFallback: ['Microsoft YaHei', 'SimHei', 'PingFang SC'],
          ),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(242)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final path = Path()
      ..moveTo(cx - 7, size.height - 2.2)
      ..quadraticBezierTo(cx - 2, size.height + 6, cx + 6, size.height - 0.5)
      ..lineTo(cx + 6, size.height - 2.4);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bongo-cat style paws that slam on key presses. [leftT]/[rightT] are the
/// remaining press times (seconds); 0 = raised.
class BongoPaws extends StatelessWidget {
  const BongoPaws({
    super.key,
    required this.leftT,
    required this.rightT,
    required this.width,
    required this.height,
  });

  final double leftT, rightT, width, height;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _PawsPainter(leftT: leftT, rightT: rightT),
        ),
      ),
    );
  }
}

class _PawsPainter extends CustomPainter {
  _PawsPainter({required this.leftT, required this.rightT});

  final double leftT, rightT;

  @override
  void paint(Canvas canvas, Size size) {
    final pawPaint = Paint()
      ..color = Colors.white.withAlpha(235)
      ..style = PaintingStyle.fill;
    final padPaint = Paint()..color = const Color(0xFFFFB7CD);
    final outline = Paint()
      ..color = const Color(0xFFC9A8B5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    void paw(double cx, double baseY, double t) {
      if (t <= 0) return; // paws only appear while a key is being hit
      final lift = -14.0; // slam down when active
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, baseY + lift), width: 40, height: 26),
        const Radius.circular(13),
      );
      canvas.drawRRect(r, pawPaint);
      canvas.drawRRect(r, outline);
      canvas.drawCircle(Offset(cx, baseY + lift), 5.5, padPaint);
    }

    final baseY = size.height - 14;
    paw(size.width * 0.18, baseY, leftT);
    paw(size.width * 0.82, baseY, rightT);
  }

  @override
  bool shouldRepaint(covariant _PawsPainter old) =>
      old.leftT != leftT || old.rightT != rightT;
}

double clamp01(double v) => v.clamp(0.0, 1.0);

double sin01(double t) => 0.5 - 0.5 * math.cos(2 * math.pi * t.clamp(0.0, 1.0));

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A circular completion ring with the percentage in the middle.
class CompletionRing extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double size;
  final double stroke;

  /// Overrides for placing the ring on a colored banner.
  final Color? trackColor;
  final Color? textColor;

  const CompletionRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 46,
    this.stroke = 5,
    this.trackColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final track = trackColor ??
        Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.8);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              value: value.clamp(0.0, 1.0),
              color: color,
              track: track,
              stroke: stroke,
            ),
          ),
          Text('${(value * 100).round()}%',
              style: TextStyle(
                  fontSize: size * 0.26,
                  fontWeight: FontWeight.w600,
                  color: textColor)),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  final double stroke;
  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, bg);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, 2 * math.pi * value, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

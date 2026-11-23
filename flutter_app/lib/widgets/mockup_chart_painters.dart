import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Neon Green upward trending line chart with arrow tip
class GreenTrendLinePainter extends CustomPainter {
  final Color color;

  GreenTrendLinePainter({this.color = const Color(0xFF10B981)});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.35),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height * 0.78);
    path.cubicTo(
      size.width * 0.22,
      size.height * 0.85,
      size.width * 0.32,
      size.height * 0.45,
      size.width * 0.48,
      size.height * 0.55,
    );
    path.cubicTo(
      size.width * 0.62,
      size.height * 0.65,
      size.width * 0.75,
      size.height * 0.15,
      size.width * 0.95,
      size.height * 0.08,
    );

    // Draw shadow / glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(path, glowPaint);

    // Draw fill underneath
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width * 0.95, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // Draw main line
    canvas.drawPath(path, linePaint);

    // Draw arrow at end
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final endX = size.width * 0.95;
    final endY = size.height * 0.08;
    final arrowPath = Path();
    arrowPath.moveTo(endX, endY - 4);
    arrowPath.lineTo(endX - 7, endY + 7);
    arrowPath.lineTo(endX + 7, endY + 7);
    arrowPath.close();
    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Cyan circular progress ring with glowing neon track
class CyanCircularProgressPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color primaryColor;
  final Color trackColor;

  CyanCircularProgressPainter({
    required this.progress,
    this.primaryColor = const Color(0xFF00F2FE),
    this.trackColor = const Color(0xFF1E293B),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - 10) / 2;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 7.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, trackPaint);

    // Progress Arc
    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
    final progressPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 7.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Glow
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.6)
      ..strokeWidth = 10.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      glowPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CyanCircularProgressPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.primaryColor != primaryColor;
}

/// Glowing Cyan smooth wave filled underneath
class CyanWavePainter extends CustomPainter {
  final Color color;

  CyanWavePainter({this.color = const Color(0xFF00F2FE)});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.38),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height * 0.60);
    path.cubicTo(
      size.width * 0.30,
      size.height * 0.85,
      size.width * 0.65,
      size.height * 0.30,
      size.width,
      size.height * 0.50,
    );

    // Glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(path, glowPaint);

    // Fill
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // Line
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

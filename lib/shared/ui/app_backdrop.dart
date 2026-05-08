import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mise_gui/app/theme/app_theme.dart';

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(gradient: colors.backdropGradient),
      child: CustomPaint(
        painter: _BackdropPainter(colors),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter(this.colors);

  final AppPalette colors;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = colors.border.withValues(alpha: 0.13)
      ..strokeWidth = 1;

    const gap = 40.0;
    for (double x = 0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    _paintGlow(
      canvas,
      rect: Rect.fromCircle(
        center: Offset(size.width * 0.85, size.height * 0.18),
        radius: 180,
      ),
      color: colors.accent.withValues(alpha: 0.08),
    );
    _paintGlow(
      canvas,
      rect: Rect.fromCircle(
        center: Offset(size.width * 0.15, size.height * 0.82),
        radius: 220,
      ),
      color: colors.info.withValues(alpha: 0.08),
    );

    final markerPaint = Paint()
      ..color = colors.textMuted.withValues(alpha: 0.1);
    for (int i = 0; i < 12; i++) {
      final dx = size.width * (0.08 + (i * 0.07));
      final dy = size.height * (0.14 + math.sin(i.toDouble()) * 0.02);
      canvas.drawCircle(Offset(dx, dy), 2.2, markerPaint);
    }
  }

  void _paintGlow(Canvas canvas, {required Rect rect, required Color color}) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ).createShader(rect);
    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Een route die zich eenmalig intekent, met een lopende stip aan de kop. Puur sfeer.
class DrawnRoute extends StatelessWidget {
  const DrawnRoute({super.key, this.top = false, this.duration = const Duration(milliseconds: 2200)});
  final bool top;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: still ? 1 : 0, end: 1),
          duration: duration,
          curve: Curves.easeInOutCubic,
          builder: (_, t, _) => CustomPaint(painter: RouteBackdropPainter(progress: t, top: top), size: Size.infinite),
        ),
      ),
    );
  }
}

class RouteBackdropPainter extends CustomPainter {
  RouteBackdropPainter({required this.progress, this.top = false});
  final double progress;

  /// Variant die alleen het bovenste deel van het scherm gebruikt (inloggen).
  final bool top;

  Path _route(Size s) {
    final w = s.width, h = s.height;
    if (top) {
      return Path()
        ..moveTo(-w * 0.05, h * 0.20)
        ..cubicTo(w * 0.20, h * 0.24, w * 0.30, h * 0.08, w * 0.52, h * 0.11)
        ..cubicTo(w * 0.78, h * 0.14, w * 0.70, h * 0.24, w * 0.90, h * 0.20)
        ..cubicTo(w * 1.02, h * 0.17, w * 1.0, h * 0.07, w * 0.86, h * 0.04);
    }
    return Path()
      // Blijft buiten de tekstband in het midden: onderlangs, rechts omhoog, bovenlangs.
      ..moveTo(w * 0.04, h * 0.84)
      ..cubicTo(w * 0.20, h * 0.70, w * 0.55, h * 0.78, w * 0.80, h * 0.71)
      ..cubicTo(w * 1.02, h * 0.64, w * 0.98, h * 0.42, w * 0.93, h * 0.30)
      ..cubicTo(w * 0.86, h * 0.12, w * 0.55, h * 0.18, w * 0.40, h * 0.10)
      ..cubicTo(w * 0.28, h * 0.04, w * 0.12, h * 0.10, w * 0.06, h * 0.20);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _route(size);
    final metric = path.computeMetrics().first;
    // Hele route heel zacht als "nog te lopen".
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.05),
    );
    final len = metric.length * progress.clamp(0.0, 1.0);
    if (len <= 1) return;
    final done = metric.extractPath(0, len);
    final shader = ui.Gradient.linear(
      Offset(0, size.height),
      Offset(size.width, 0),
      [RwColors.accentDeep.withValues(alpha: 0.15), RwColors.accent.withValues(alpha: 0.55)],
    );
    canvas.drawPath(
      done,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = RwColors.accent.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(
      done,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
    final tip = metric.getTangentForOffset(len)?.position;
    if (tip != null) {
      canvas.drawCircle(tip, 14, Paint()..color = RwColors.accent.withValues(alpha: 0.18));
      canvas.drawCircle(tip, 5.5, Paint()..color = RwColors.accent);
      canvas.drawCircle(tip, 2.2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant RouteBackdropPainter old) => old.progress != progress;
}


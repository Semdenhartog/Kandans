import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Een hardloper in lijnstijl (eigen ontwerp, in de huisstijl), met een rustige loopcyclus.
/// [phase] 0..1 is één volledige pas (links + rechts).
class RunnerPainter extends CustomPainter {
  RunnerPainter({required this.phase, required this.color, this.accent, this.stroke = 3});

  final double phase;
  final Color color;
  final Color? accent;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height;
    final cx = size.width / 2;
    final a = phase * 2 * math.pi;
    final bob = -math.cos(a * 2).abs() * s * 0.025;

    final p = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final hip = Offset(cx, s * 0.55 + bob);
    final neck = hip + Offset(s * 0.06, -s * 0.28);
    final head = neck + Offset(s * 0.03, -s * 0.09);

    // Benen: dij en scheen, tegengesteld.
    Offset knee(double ang) => hip + Offset(math.sin(ang) * s * 0.17, math.cos(ang) * s * 0.17);
    Offset foot(Offset k, double ang, double lift) =>
        k + Offset(math.sin(ang - 0.4 - lift) * s * 0.17, math.cos(ang - 0.4 - lift) * s * 0.17);
    for (final side in [0.0, math.pi]) {
      final sw = math.sin(a + side);
      final thigh = sw * 0.75;
      final lift = math.max(0.0, -math.cos(a + side)) * 1.3;
      final k = knee(thigh);
      final f = foot(k, thigh, lift);
      final back = side == math.pi;
      final legPaint = back ? (Paint()..color = color.withValues(alpha: 0.45)..strokeWidth = stroke..strokeCap = StrokeCap.round..style = PaintingStyle.stroke) : p;
      canvas.drawPath(Path()..moveTo(hip.dx, hip.dy)..lineTo(k.dx, k.dy)..lineTo(f.dx, f.dy), legPaint);
    }

    // Romp en hoofd.
    canvas.drawLine(hip, neck, p);
    canvas.drawCircle(head, s * 0.065, p..style = PaintingStyle.stroke);

    // Armen: tegengesteld aan de benen.
    final shoulder = Offset.lerp(hip, neck, 0.85)!;
    for (final side in [0.0, math.pi]) {
      final sw = math.sin(a + side + math.pi);
      final elbow = shoulder + Offset(math.sin(sw * 0.9) * s * 0.12, math.cos(sw * 0.9) * s * 0.12);
      final hand = elbow + Offset(math.sin(sw * 0.9 - 1.6) * s * 0.11, math.cos(sw * 0.9 - 1.6) * s * 0.11);
      final back = side == math.pi;
      final armPaint = back ? (Paint()..color = color.withValues(alpha: 0.45)..strokeWidth = stroke..strokeCap = StrokeCap.round..style = PaintingStyle.stroke) : p;
      canvas.drawPath(Path()..moveTo(shoulder.dx, shoulder.dy)..lineTo(elbow.dx, elbow.dy)..lineTo(hand.dx, hand.dy), armPaint);
    }

    // Kleine accentstip: het horloge.
    if (accent != null) {
      final sw = math.sin(a + math.pi);
      final elbow = shoulder + Offset(math.sin(sw * 0.9) * s * 0.12, math.cos(sw * 0.9) * s * 0.12);
      final hand = elbow + Offset(math.sin(sw * 0.9 - 1.6) * s * 0.11, math.cos(sw * 0.9 - 1.6) * s * 0.11);
      canvas.drawCircle(Offset.lerp(elbow, hand, 0.75)!, stroke * 0.9, Paint()..color = accent!);
    }
  }

  @override
  bool shouldRepaint(covariant RunnerPainter old) => old.phase != phase || old.color != color;
}

/// Lopend figuurtje als widget.
class RunnerFigure extends StatefulWidget {
  const RunnerFigure({super.key, this.size = 80, this.color, this.accent, this.speed = 1});
  final double size;
  final Color? color;
  final Color? accent;
  final double speed;

  @override
  State<RunnerFigure> createState() => _RunnerFigureState();
}

class _RunnerFigureState extends State<RunnerFigure> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Duration(milliseconds: (900 / widget.speed).round()));

  @override
  void initState() {
    super.initState();
    if (!WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            size: Size(widget.size * 0.7, widget.size),
            painter: RunnerPainter(
              phase: _c.value,
              color: widget.color ?? Theme.of(context).colorScheme.onSurface,
              accent: widget.accent,
              stroke: widget.size / 26,
            ),
          ),
        ),
      );
}

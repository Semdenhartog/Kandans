import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Kleuren van de aura per dagdeel: ochtendroze, daggoud, avondoranje, nachtblauw.
List<Color> auraColors(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 9) return [RwColors.accentLight, const Color(0xFFE6BE8A)];
  if (h >= 9 && h < 17) return [RwColors.accentLight, RwColors.accent];
  if (h >= 17 && h < 22) return [RwColors.accentDeep, RwColors.accent];
  return const [Color(0xFF5B6B8A), Color(0xFF3F4B66)];
}

/// Zachte gloed bovenin het scherm, die meekleurt met het dagdeel. Valt bij overgangen zacht over.
class RwAura extends StatelessWidget {
  const RwAura({super.key});

  @override
  Widget build(BuildContext context) {
    final c = auraColors(DateTime.now());
    return IgnorePointer(
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(color: RwColors.background),
          child: Stack(children: [
            Positioned(
              top: -220,
              left: -160,
              child: _blob(c[0], 520, 0.16),
            ),
            Positioned(
              top: -260,
              right: -200,
              child: _blob(c[1], 560, 0.11),
            ),
            // Lichte papierstructuur (zoals kadans.fit): één keer getekend, kost geen accu.
            Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: PaperGrainPainter(dark: RwColors.isDark)))),
          ]),
        ),
      ),
    );
  }

  Widget _blob(Color color, double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)]),
        ),
      );
}

/// Fijne korrel als op papier: vaste puntjes, licht en donker door elkaar.
class PaperGrainPainter extends CustomPainter {
  const PaperGrainPainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rnd = math.Random(7);
    final n = (size.width * size.height / 70).clamp(0, 9000).toInt();
    final darkPts = <Offset>[], lightPts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final o = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      (i.isEven ? darkPts : lightPts).add(o);
    }
    canvas.drawPoints(
        ui.PointMode.points,
        darkPts,
        Paint()
          ..color = const Color(0xFF3A2C1E).withValues(alpha: dark ? 0.10 : 0.055)
          ..strokeWidth = 1);
    canvas.drawPoints(
        ui.PointMode.points,
        lightPts,
        Paint()
          ..color = Colors.white.withValues(alpha: dark ? 0.025 : 0.10)
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant PaperGrainPainter old) => old.dark != dark;
}

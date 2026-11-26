import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'achtergrond.dart';

/// Achtergrond onder alle schermen: een eigen beeld met zachte kleurvlakken (standaard `glas_vlekken`), waar het matglas van de kaarten overheen ligt.
class RwAura extends StatelessWidget {
  const RwAura({super.key, this.beeld = 'glas_vlekken'});
  final String beeld;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: achtergrondBox(beeld),
          child: Stack(children: [
            // Lichte papierstructuur (zoals kadans.fit): één keer getekend, kost geen accu.
            Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: PaperGrainPainter(dark: RwColors.isDark)))),
          ]),
        ),
      ),
    );
  }
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

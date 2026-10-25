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

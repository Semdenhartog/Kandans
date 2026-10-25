import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Aftelling als een klapbord: elk cijfer op een eigen tegeltje met een naad in het midden.
class FlipDigits extends StatelessWidget {
  const FlipDigits({super.key, required this.text, this.size = 1.0});
  final String text;

  /// Schaal: 1 = klein (op Vandaag), 1.6 = groot (wedstrijdpagina).
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final ch in text.split(''))
            Container(
              width: 28 * size,
              height: 40 * size,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF2C2620), Color(0xFF221D18), Color(0xFF151210), Color(0xFF1B1714)],
                  stops: [0, 0.499, 0.501, 1],
                ),
                border: Border.all(color: RwColors.accent.withValues(alpha: 0.25)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 6, offset: const Offset(0, 3))],
              ),
              child: Stack(alignment: Alignment.center, children: [
                Text(ch,
                    style: TextStyle(
                        fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: 26 * size, color: rwZandAvond.accent, height: 1)),
                // De naad van het klapbord.
                Positioned(left: 0, right: 0, child: Container(height: 1.2, color: Colors.black.withValues(alpha: 0.7))),
              ]),
            ),
        ],
      );
}

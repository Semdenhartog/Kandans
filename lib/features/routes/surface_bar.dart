import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';

/// Compacte balk met de ondergrond van een route (live onder het tekenscherm).
class SurfaceBar extends StatelessWidget {
  const SurfaceBar(this.meters, {super.key});

  /// Meters per soort: 'verhard', 'klinkers', 'halfverhard', 'onverhard', 'onbekend'.
  final Map<String, double> meters;

  static const order = ['verhard', 'klinkers', 'halfverhard', 'onverhard', 'onbekend'];
  static const colors = {
    'verhard': Color(0xFF8D8D98),
    'klinkers': Color(0xFFC77D4A),
    'halfverhard': Color(0xFFD9B44A),
    'onverhard': Color(0xFF5BAE6B),
    'onbekend': Color(0xFF4A4A55),
  };
  static const short = {
    'verhard': 'Verhard',
    'klinkers': 'Klinkers',
    'halfverhard': 'Halfverhard',
    'onverhard': 'Onverhard',
    'onbekend': 'Onbekend',
  };

  @override
  Widget build(BuildContext context) {
    final types = [for (final t in order) if ((meters[t] ?? 0) > 0) t];
    final total = types.fold<double>(0, (a, t) => a + meters[t]!);
    if (total <= 0) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(RwRadius.s),
        child: SizedBox(
          height: 8,
          child: Row(children: [
            for (final t in types) Expanded(flex: math.max(1, (meters[t]! / total * 1000).round()), child: ColoredBox(color: colors[t]!)),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 12, runSpacing: 4, children: [
        for (final t in types)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[t], shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text('${tr(short[t]!)} ${(meters[t]! / total * 100).round()}%', style: TextStyle(color: RwColors.muted, fontSize: 12)),
          ]),
      ]),
    ]);
  }
}

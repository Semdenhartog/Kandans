import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'landscape.dart';
import 'weather_icon.dart';

/// Korte uitleg-animatie (loopt rond, ~9 s): de uren van de middag met hun weer,
/// de scores groeien, Kadans zoekt langs de uren en het beste moment gaat gloeien.
class BestMomentDemo extends StatefulWidget {
  const BestMomentDemo({super.key, this.height = 190});
  final double height;

  @override
  State<BestMomentDemo> createState() => _BestMomentDemoState();
}

class _BestMomentDemoState extends State<BestMomentDemo> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 9));

  @override
  void initState() {
    super.initState();
    if (WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      _c.value = 0.9;
    } else {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [RwColors.accent.withValues(alpha: 0.12), RwColors.surface.withValues(alpha: 0.4)],
                ),
              ),
              child: Stack(children: [
                const Positioned.fill(child: KadansLandscape(opacity: 0.6, showPath: false)),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (_, _) => CustomPaint(
                      painter: _DemoPainter(
                        t: _c.value,
                        text: RwColors.text,
                        muted: RwColors.subtle,
                        accent: RwColors.accent,
                        good: RwColors.good,
                        bar: RwColors.bar,
                        textScale: MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _DemoPainter extends CustomPainter {
  _DemoPainter({required this.t, required this.text, required this.muted, required this.accent, required this.good, required this.bar, required this.textScale});
  final double t;
  final Color text, muted, accent, good, bar;
  final double textScale;

  static const _hours = [12, 13, 14, 15, 16, 17, 18, 19];
  static const _codes = [63, 61, 3, 2, 0, 1, 2, 3];
  static const _scores = [34, 41, 58, 73, 93, 86, 71, 55];
  static const _best = 4;

  void _text(Canvas c, String s, Offset center, double size, Color color, {FontWeight w = FontWeight.w600}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size * textScale, fontWeight: w, fontFamily: RwFonts.display)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final n = _hours.length;
    final colW = w / (n + 0.6);
    final left = colW * 0.3;
    final barBottom = h - 26;
    final barTop = 58.0;
    final maxBar = barBottom - barTop;

    // Fases: 0–0.4 groeien, 0.4–0.65 zoeken, 0.65–1 gevonden.
    final grow = (t / 0.4).clamp(0.0, 1.0);
    final scan = ((t - 0.4) / 0.25).clamp(0.0, 1.0);
    final found = ((t - 0.65) / 0.1).clamp(0.0, 1.0);
    final fade = t > 0.94 ? (1 - (t - 0.94) / 0.06) : 1.0;

    for (var i = 0; i < n; i++) {
      final cx = left + colW * (i + 0.5);
      final local = (grow * n - i).clamp(0.0, 1.0);
      final eased = Curves.easeOutBack.transform(local).clamp(0.0, 1.15);
      final bh = maxBar * _scores[i] / 100 * eased * fade;
      final isBest = i == _best && found > 0;
      final color = isBest ? accent : Color.lerp(bar, good, _scores[i] / 100 * 0.8)!;
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(cx - colW * 0.28, barBottom - bh, colW * 0.56, bh), const Radius.circular(6));
      if (isBest) {
        final glow = 0.5 + 0.5 * math.sin(t * 40);
        canvas.drawRRect(rect.inflate(4 + 2 * glow), Paint()..color = accent.withValues(alpha: 0.25 * found));
      }
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: (isBest ? 1.0 : 0.75) * fade));
      // Weericoon boven elke kolom.
      if (local > 0) {
        canvas.save();
        final s = colW * 0.7;
        canvas.translate(cx - s / 2, 8 + (1 - local) * 8);
        WeatherGlyphPainter(glyph: glyphFor(_codes[i]), t: t * 3 % 1, sun: const Color(0xFFFFB547), cloud: text, drop: const Color(0xFF5AA9FF))
            .paint(canvas, Size.square(s));
        canvas.restore();
      }
      _text(canvas, '${_hours[i]}', Offset(cx, barBottom + 12), 11, isBest ? accent : muted);
    }

    // De zoeker die langs de uren gaat.
    if (scan > 0 && scan < 1) {
      final x = left + colW * (scan * (n - 0.001));
      canvas.drawLine(Offset(x, barTop - 6), Offset(x, barBottom),
          Paint()
            ..color = text.withValues(alpha: 0.5)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round);
    }

    // Gevonden: label boven de beste kolom.
    if (found > 0 && fade > 0) {
      final cx = left + colW * (_best + 0.5);
      final bh = maxBar * _scores[_best] / 100;
      final y = barBottom - bh - 14;
      final label = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, y), width: 86 * textScale, height: 22 * textScale), const Radius.circular(11));
      canvas.drawRRect(label, Paint()..color = accent.withValues(alpha: found * fade));
      _text(canvas, '16:00 · 93', Offset(cx, y), 12, Colors.black.withValues(alpha: found * fade), w: FontWeight.w800);
    }
  }

  @override
  bool shouldRepaint(covariant _DemoPainter old) => old.t != t || old.text != text;
}

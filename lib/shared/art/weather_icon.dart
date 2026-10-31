import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

enum WeatherGlyph { sun, moon, partly, partlyNight, cloud, fog, drizzle, rain, snow, thunder }

/// WMO-weercode (Open-Meteo) naar een plaatje.
WeatherGlyph glyphFor(int? code, {bool day = true}) {
  final c = code ?? 0;
  if (c >= 95) return WeatherGlyph.thunder;
  if ((c >= 71 && c <= 77) || c == 85 || c == 86) return WeatherGlyph.snow;
  if (c >= 61 && c <= 67 || c >= 80 && c <= 82) return WeatherGlyph.rain;
  if (c >= 51 && c <= 57) return WeatherGlyph.drizzle;
  if (c == 45 || c == 48) return WeatherGlyph.fog;
  if (c == 3) return WeatherGlyph.cloud;
  if (c == 1 || c == 2) return day ? WeatherGlyph.partly : WeatherGlyph.partlyNight;
  return day ? WeatherGlyph.sun : WeatherGlyph.moon;
}

/// Klein bewegend weericoon: draaiende zonnestralen, drijvende wolk, vallende druppels,
/// dwarrelende sneeuw, een flits bij onweer. Staat stil als "minder beweging" aan staat.
class AnimatedWeatherIcon extends StatefulWidget {
  const AnimatedWeatherIcon({super.key, required this.code, this.day = true, this.size = 32});
  final int? code;
  final bool day;
  final double size;

  @override
  State<AnimatedWeatherIcon> createState() => _AnimatedWeatherIconState();
}

class _AnimatedWeatherIconState extends State<AnimatedWeatherIcon> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  late final bool _still = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  @override
  void initState() {
    super.initState();
    if (!_still) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: WeatherGlyphPainter(
                glyph: glyphFor(widget.code, day: widget.day),
                t: _still ? 0.25 : _c.value,
                sun: const Color(0xFFFFB547),
                cloud: RwColors.text,
                drop: const Color(0xFF5AA9FF),
              ),
            ),
          ),
        ),
      );
}

class WeatherGlyphPainter extends CustomPainter {
  WeatherGlyphPainter({required this.glyph, required this.t, required this.sun, required this.cloud, required this.drop});
  final WeatherGlyph glyph;
  final double t;
  final Color sun, cloud, drop;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final a = t * 2 * math.pi;
    switch (glyph) {
      case WeatherGlyph.sun:
        _sun(canvas, Offset(s / 2, s / 2), s * 0.2, a);
      case WeatherGlyph.moon:
        _moon(canvas, Offset(s / 2, s / 2), s * 0.24, a);
      case WeatherGlyph.partly:
        _sun(canvas, Offset(s * 0.36, s * 0.36), s * 0.15, a);
        _cloud(canvas, Offset(s * 0.58 + math.sin(a) * s * 0.03, s * 0.6), s * 0.5, 1.45);
      case WeatherGlyph.partlyNight:
        _moon(canvas, Offset(s * 0.36, s * 0.36), s * 0.17, a);
        _cloud(canvas, Offset(s * 0.58 + math.sin(a) * s * 0.03, s * 0.6), s * 0.5, 1.45);
      case WeatherGlyph.cloud:
        _cloud(canvas, Offset(s * 0.4 + math.sin(a) * s * 0.03, s * 0.42), s * 0.4, 0.45);
        _cloud(canvas, Offset(s * 0.55 - math.sin(a) * s * 0.04, s * 0.58), s * 0.58, 0.9);
      case WeatherGlyph.fog:
        final p = Paint()
          ..color = cloud.withValues(alpha: 0.7)
          ..strokeWidth = s * 0.07
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 3; i++) {
          final dx = math.sin(a + i * 1.7) * s * 0.08;
          final y = s * (0.32 + i * 0.18);
          canvas.drawLine(Offset(s * 0.18 + dx, y), Offset(s * 0.82 + dx - (i == 1 ? s * 0.12 : 0), y), p);
        }
      case WeatherGlyph.drizzle || WeatherGlyph.rain:
        final heavy = glyph == WeatherGlyph.rain;
        _cloud(canvas, Offset(s * 0.5, s * 0.4), s * 0.62, 0.9);
        final p = Paint()
          ..color = drop
          ..strokeWidth = s * (heavy ? 0.06 : 0.045)
          ..strokeCap = StrokeCap.round;
        final n = heavy ? 3 : 2;
        for (var i = 0; i < n; i++) {
          final f = (t * (heavy ? 2 : 1.4) + i / n) % 1.0;
          final x = s * (0.35 + i * (0.3 / (n - 1 == 0 ? 1 : n - 1)));
          final y = s * 0.6 + f * s * 0.32;
          final len = s * (heavy ? 0.12 : 0.07);
          canvas.drawLine(Offset(x - f * s * 0.03, y), Offset(x - f * s * 0.03 - len * 0.25, y + len), p..color = drop.withValues(alpha: 1 - f * 0.8));
        }
      case WeatherGlyph.snow:
        _cloud(canvas, Offset(s * 0.5, s * 0.4), s * 0.62, 0.9);
        for (var i = 0; i < 3; i++) {
          final f = (t * 0.8 + i / 3) % 1.0;
          final x = s * (0.33 + i * 0.17) + math.sin(a * 2 + i) * s * 0.04;
          final y = s * 0.62 + f * s * 0.3;
          canvas.drawCircle(Offset(x, y), s * 0.045, Paint()..color = cloud.withValues(alpha: 0.9 - f * 0.6));
        }
      case WeatherGlyph.thunder:
        _cloud(canvas, Offset(s * 0.5, s * 0.38), s * 0.64, 0.9);
        final flash = (t % 0.5) < 0.06 || ((t + 0.08) % 0.5) < 0.04;
        final bolt = Path()
          ..moveTo(s * 0.52, s * 0.55)
          ..lineTo(s * 0.4, s * 0.76)
          ..lineTo(s * 0.5, s * 0.76)
          ..lineTo(s * 0.44, s * 0.95)
          ..lineTo(s * 0.62, s * 0.7)
          ..lineTo(s * 0.52, s * 0.7)
          ..close();
        canvas.drawPath(bolt, Paint()..color = sun.withValues(alpha: flash ? 1 : 0.75));
        if (flash) {
          canvas.drawCircle(Offset(s * 0.5, s * 0.7), s * 0.3,
              Paint()..shader = RadialGradient(colors: [sun.withValues(alpha: 0.35), sun.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: Offset(s * 0.5, s * 0.7), radius: s * 0.3)));
        }
    }
  }

  void _sun(Canvas canvas, Offset c, double r, double a) {
    final glow = 1 + 0.08 * math.sin(a * 2);
    canvas.drawCircle(c, r * 1.9 * glow,
        Paint()..shader = RadialGradient(colors: [sun.withValues(alpha: 0.3), sun.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r * 1.9 * glow)));
    final ray = Paint()
      ..color = sun
      ..strokeWidth = r * 0.28
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final ang = a * 0.25 + i * math.pi / 4;
      final d = Offset(math.cos(ang), math.sin(ang));
      canvas.drawLine(c + d * r * 1.35, c + d * r * 1.75, ray);
    }
    canvas.drawCircle(c, r, Paint()..color = sun);
  }

  void _moon(Canvas canvas, Offset c, double r, double a) {
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: c, radius: r)),
      Path()..addOval(Rect.fromCircle(center: c + Offset(r * 0.55, -r * 0.35), radius: r * 0.85)),
    );
    canvas.drawPath(moon, Paint()..color = const Color(0xFFE8D9A8));
    for (var i = 0; i < 2; i++) {
      final tw = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(a * 2 + i * 2));
      canvas.drawCircle(c + Offset(r * (1.1 + i * 0.3), -r * (0.9 - i * 1.3)), r * 0.09, Paint()..color = cloud.withValues(alpha: tw));
    }
  }

  void _cloud(Canvas canvas, Offset c, double w, double alpha) {
    final h = w * 0.42;
    var shape = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, h * 0.2), width: w, height: h * 0.6), Radius.circular(h * 0.3)));
    shape = Path.combine(PathOperation.union, shape, Path()..addOval(Rect.fromCircle(center: c + Offset(-w * 0.18, 0), radius: h * 0.38)));
    shape = Path.combine(PathOperation.union, shape, Path()..addOval(Rect.fromCircle(center: c + Offset(w * 0.08, -h * 0.15), radius: h * 0.5)));
    canvas.drawPath(shape, Paint()..color = cloud.withValues(alpha: 0.62 * alpha));
  }

  @override
  bool shouldRepaint(covariant WeatherGlyphPainter old) => old.t != t || old.glyph != glyph || old.cloud != cloud;
}

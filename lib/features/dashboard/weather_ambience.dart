import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';

enum _Kind { sun, stars, clouds, rain, snow }

_Kind _kindOf(HourWeather w) {
  final c = w.weatherCode ?? 0;
  if ((c >= 71 && c <= 77) || c == 85 || c == 86) return _Kind.snow;
  if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82) || c >= 95) return _Kind.rain;
  if (c >= 2) return _Kind.clouds;
  return w.isDay ? _Kind.sun : _Kind.stars;
}

/// Zachte, levende weerachtergrond in de hoofdkaart: regen die met de wind meewaait, sneeuw,
/// drijvende wolken, een zonnegloed of fonkelende sterren. Heel subtiel, zodat de tekst leesbaar blijft.
class WeatherAmbience extends StatefulWidget {
  const WeatherAmbience({super.key, required this.weather});
  final HourWeather weather;

  @override
  State<WeatherAmbience> createState() => _WeatherAmbienceState();
}

class _WeatherAmbienceState extends State<WeatherAmbience> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 10));
  final _seed = math.Random(4);
  late final _bits = List.generate(46, (_) => (x: _seed.nextDouble(), y: _seed.nextDouble(), s: 0.6 + _seed.nextDouble() * 0.8));
  bool _still = false;

  @override
  void initState() {
    super.initState();
    _still = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (!_still) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(
              painter: _AmbiencePainter(_kindOf(widget.weather), _still ? 0.3 : _c.value, _bits, widget.weather.windSpeed),
              size: Size.infinite,
            ),
          ),
        ),
      );
}

class _AmbiencePainter extends CustomPainter {
  _AmbiencePainter(this.kind, this.t, this.bits, this.wind);
  final _Kind kind;
  final double t;
  final List<({double x, double y, double s})> bits;
  final double wind;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    switch (kind) {
      case _Kind.sun:
        final pulse = 0.85 + 0.15 * math.sin(t * 2 * math.pi);
        final c = Offset(w * 0.88, h * 0.08);
        canvas.drawCircle(
          c,
          w * 0.55 * pulse,
          Paint()
            ..shader = RadialGradient(colors: [
              RwColors.accentLight.withValues(alpha: 0.22),
              RwColors.accent.withValues(alpha: 0.06),
              Colors.transparent,
            ], stops: const [0, 0.45, 1])
                .createShader(Rect.fromCircle(center: c, radius: w * 0.55 * pulse)),
        );
        // Zachte stralen die langzaam draaien.
        final ray = Paint()
          ..color = RwColors.accentLight.withValues(alpha: 0.05)
          ..strokeWidth = 18
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 7; i++) {
          final a = t * 2 * math.pi * 0.1 + i * math.pi / 3.5;
          canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * w * 0.12, c + Offset(math.cos(a), math.sin(a)) * w * 0.45, ray);
        }
      case _Kind.stars:
        for (final (i, b) in bits.indexed) {
          final tw = 0.5 + 0.5 * math.sin((t * 2 + b.x * 3 + i) * math.pi);
          canvas.drawCircle(Offset(b.x * w, b.y * h * 0.7), 0.8 + b.s, Paint()..color = Colors.white.withValues(alpha: 0.08 + 0.22 * tw));
        }
      case _Kind.clouds:
        for (var i = 0; i < 4; i++) {
          final speed = 0.6 + i * 0.25;
          final x = ((t * speed + i * 0.3) % 1.4 - 0.2) * w;
          final y = h * (0.12 + i * 0.2);
          final r = w * (0.18 + 0.05 * i);
          canvas.drawOval(
            Rect.fromCenter(center: Offset(x, y), width: r * 2.4, height: r),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.035)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
          );
        }
      case _Kind.rain:
        final slant = (wind / 40).clamp(0.0, 0.6);
        final p = Paint()
          ..color = const Color(0xFF7CC4FF).withValues(alpha: 0.16)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round;
        for (final b in bits) {
          final y = ((b.y + t * 3 * b.s) % 1.1 - 0.05) * h;
          final x = (b.x * w) + slant * y * 0.4 - slant * h * 0.2;
          canvas.drawLine(Offset(x, y), Offset(x + slant * 10, y + 12 * b.s), p);
        }
      case _Kind.snow:
        for (final b in bits) {
          final y = ((b.y + t * 0.8 * b.s) % 1.05) * h;
          final x = b.x * w + 8 * math.sin((t * 4 + b.x * 8) * math.pi);
          canvas.drawCircle(Offset(x, y), 1.2 + b.s * 1.4, Paint()..color = Colors.white.withValues(alpha: 0.22));
        }
    }
  }

  @override
  bool shouldRepaint(covariant _AmbiencePainter old) => old.t != t || old.kind != kind;
}

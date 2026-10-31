import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'tilt.dart';

/// Hollands landschap in lijnen en vlakken, dat met de maand meekleurt:
/// kale bomen en sneeuw in de winter, bloesem en tulpen in de lente, paarse hei in augustus,
/// vallende bladeren in de herfst. Met een kronkelpad (je route) naar de horizon.
/// Gebruikt in de hoofdkaart op Vandaag, bij lege schermen en als seizoensplaatje.
class Season {
  const Season._(this.month);
  final int month;
  factory Season.of(DateTime d) => Season._(d.month);

  bool get winter => month == 12 || month <= 2;
  bool get spring => month >= 3 && month <= 5;
  bool get summer => month >= 6 && month <= 8;
  bool get autumn => month >= 9 && month <= 11;
  bool get bareTrees => month == 12 || month <= 3 || month == 11;
  bool get blossom => month == 4 || month == 5;
  bool get tulips => month == 4;
  bool get heather => month == 8 || month == 9;
  bool get fallingLeaves => month == 10 || month == 11;
  bool get snow => month == 12 || month == 1 || month == 2;
  bool get fog => month == 11;

  /// Kleur van de boomkruinen.
  Color get crown => switch (month) {
        9 => const Color(0xFF8A9A4A),
        10 => const Color(0xFFC9772E),
        11 => const Color(0xFFA9622F),
        4 || 5 => const Color(0xFF7FA55A),
        _ => const Color(0xFF5E8A4E),
      };

  /// Kleur van het land vooraan.
  Color get meadow => switch (month) {
        12 || 1 || 2 => const Color(0xFF9DA7A3),
        3 || 4 || 5 => const Color(0xFF7DAA5C),
        6 || 7 => const Color(0xFF6C9A50),
        8 || 9 => const Color(0xFF8C7A9E),
        _ => const Color(0xFF9A8A5A),
      };
}

class KadansLandscape extends StatefulWidget {
  const KadansLandscape({
    super.key,
    this.date,
    this.wind = 10,
    this.opacity = 1,
    this.animate = true,
    this.parallax = true,
    this.showPath = true,
  });

  final DateTime? date;
  final double wind;
  final double opacity;
  final bool animate;
  final bool parallax;
  final bool showPath;

  @override
  State<KadansLandscape> createState() => _KadansLandscapeState();
}

class _KadansLandscapeState extends State<KadansLandscape> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 12));
  late final bool _still = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  @override
  void initState() {
    super.initState();
    if (widget.animate && !_still) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final season = Season.of(widget.date ?? DateTime.now());
    final tilt = widget.parallax && !_still ? Tilt.instance : null;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_c, if (tilt != null) tilt]),
            builder: (_, _) => CustomPaint(
              size: Size.infinite,
              painter: LandscapePainter(
                season: season,
                t: _still ? 0.2 : _c.value,
                tilt: tilt?.value ?? Offset.zero,
                wind: widget.wind,
                opacity: widget.opacity,
                showPath: widget.showPath,
                ink: RwColors.text,
                accent: RwColors.accent,
                dark: RwColors.isDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LandscapePainter extends CustomPainter {
  LandscapePainter({
    required this.season,
    required this.t,
    required this.tilt,
    required this.wind,
    required this.opacity,
    required this.showPath,
    required this.ink,
    required this.accent,
    required this.dark,
  });

  final Season season;
  final double t;
  final Offset tilt;
  final double wind;
  final double opacity;
  final bool showPath;
  final Color ink, accent;
  final bool dark;

  Color _c(Color c, double a) => c.withValues(alpha: (a * opacity).clamp(0.0, 1.0));

  // Vaste "willekeur", zodat het landschap elke keer hetzelfde is.
  double _r(int i) {
    final x = math.sin(i * 12.9898 + 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final sway = (wind / 30).clamp(0.2, 1.4);
    final dim = dark ? 0.75 : 1.0;

    // 1) Verre heuvelrug (beweegt het minst mee).
    final far = Offset(tilt.dx * 4, tilt.dy * 2);
    final farPath = Path()..moveTo(0, h);
    for (var x = 0.0; x <= w; x += 6) {
      final y = h * 0.52 + math.sin(x / w * math.pi * 2.2 + 0.6) * h * 0.05 + math.sin(x / w * math.pi * 5.3) * h * 0.02;
      farPath.lineTo(x + far.dx, y + far.dy);
    }
    farPath
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(farPath, Paint()..color = _c(ink, 0.05 * dim));

    // 2) Bomenrij op de middelste heuvel.
    final mid = Offset(tilt.dx * 9, tilt.dy * 4);
    double midY(double x) => h * 0.64 + math.sin(x / w * math.pi * 1.6 + 1.2) * h * 0.045;
    final midPath = Path()..moveTo(0, h);
    for (var x = 0.0; x <= w; x += 6) {
      midPath.lineTo(x + mid.dx, midY(x) + mid.dy);
    }
    midPath
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(midPath, Paint()..color = _c(season.meadow, 0.16 * dim));

    final treeCount = (w / 26).clamp(6, 24).round();
    for (var i = 0; i < treeCount; i++) {
      final x = (i + 0.5 + (_r(i) - 0.5) * 0.6) / treeCount * w;
      final base = Offset(x + mid.dx, midY(x) + mid.dy + 2);
      final th = h * (0.07 + _r(i + 40) * 0.06);
      final bend = math.sin((t * 2 + _r(i + 7)) * math.pi * 2) * 1.6 * sway;
      final top = base + Offset(bend, -th);
      final trunk = Paint()
        ..color = _c(ink, 0.16 * dim)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(base, top, trunk);
      if (season.bareTrees) {
        // Kale takken.
        for (var b = 0; b < 3; b++) {
          final p = Offset.lerp(base, top, 0.45 + b * 0.18)!;
          final len = th * (0.35 - b * 0.08);
          canvas.drawLine(p, p + Offset(-len * 0.7 + bend * 0.5, -len * 0.6), trunk..strokeWidth = 1.1);
          canvas.drawLine(p, p + Offset(len * 0.7 + bend * 0.5, -len * 0.55), trunk);
        }
        if (season.snow) {
          canvas.drawCircle(top, 1.8, Paint()..color = _c(Colors.white, 0.5));
        }
      } else {
        final r = th * (0.38 + _r(i + 3) * 0.12);
        final crown = Paint()..color = _c(season.crown, 0.32 * dim);
        canvas.drawCircle(top + Offset(0, r * 0.4), r, crown);
        canvas.drawCircle(top + Offset(-r * 0.55, r * 0.75), r * 0.7, crown);
        canvas.drawCircle(top + Offset(r * 0.55, r * 0.75), r * 0.7, crown);
        if (season.blossom && i.isEven) {
          for (var k = 0; k < 6; k++) {
            final a = _r(i * 10 + k) * math.pi * 2;
            final d = _r(i * 10 + k + 5) * r;
            canvas.drawCircle(top + Offset(math.cos(a) * d, r * 0.4 + math.sin(a) * d), 1.4,
                Paint()..color = _c(const Color(0xFFF4C6D2), 0.7));
          }
        }
      }
    }

    // 3) Mist in november: zachte banden die langzaam schuiven.
    if (season.fog) {
      for (var i = 0; i < 3; i++) {
        final y = h * (0.6 + i * 0.07);
        final x = ((t * (0.3 + i * 0.1) + i * 0.33) % 1.0) * w;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: w * 0.9, height: h * 0.05),
          Paint()
            ..color = _c(ink, 0.05)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }
    }

    // 4) Voorgrond: wei met kronkelpad.
    final near = Offset(tilt.dx * 16, tilt.dy * 6);
    double nearY(double x) => h * 0.8 + math.sin(x / w * math.pi * 1.1 + 2.4) * h * 0.04;
    final nearPath = Path()..moveTo(0, h);
    for (var x = 0.0; x <= w; x += 6) {
      nearPath.lineTo(x + near.dx, nearY(x) + near.dy);
    }
    nearPath
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(nearPath, Paint()..color = _c(season.snow ? Colors.white : season.meadow, (season.snow ? 0.22 : 0.22) * dim));

    if (showPath) {
      final path = Path();
      const n = 40;
      for (var i = 0; i <= n; i++) {
        final f = i / n;
        final y = h + 4 - f * (h * 0.36);
        final x = w * 0.5 + math.sin(f * math.pi * 2.4) * w * 0.16 * (1 - f) + near.dx * (1 - f) + mid.dx * f;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      final metric = path.computeMetrics().first;
      final dash = Paint()
        ..color = _c(accent, 0.55)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      // De streepjes lopen langzaam naar de horizon, alsof iemand er loopt.
      final shift = (t * 14 * 8) % 14;
      for (var d = shift; d < metric.length; d += 14) {
        final f = d / metric.length;
        dash.strokeWidth = 2.6 - f * 1.6;
        canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), dash);
      }
    }

    // 5) Seizoensdetails vooraan.
    if (season.heather) {
      for (var i = 0; i < 70; i++) {
        final x = _r(i + 300) * w;
        final y = nearY(x) + near.dy + _r(i + 400) * (h - nearY(x)) * 0.9;
        canvas.drawCircle(Offset(x + near.dx, y), 1.6, Paint()..color = _c(const Color(0xFFA77BC9), 0.45));
      }
    }
    if (season.spring) {
      final colors = season.tulips
          ? const [Color(0xFFE5484D), Color(0xFFF2C14E), Color(0xFFE77FB0)]
          : const [Color(0xFFF2E6A8), Color(0xFFFFFFFF), Color(0xFFC8B6F0)];
      for (var i = 0; i < 26; i++) {
        final x = _r(i + 500) * w;
        final y = nearY(x) + near.dy + 6 + _r(i + 600) * (h - nearY(x)) * 0.7;
        final c = colors[i % colors.length];
        final stem = Paint()
          ..color = _c(const Color(0xFF5E8A4E), 0.4)
          ..strokeWidth = 1;
        canvas.drawLine(Offset(x + near.dx, y), Offset(x + near.dx, y - 6), stem);
        canvas.drawCircle(Offset(x + near.dx, y - 7), season.tulips ? 2.4 : 1.8, Paint()..color = _c(c, 0.6));
      }
    }
    if (season.fallingLeaves) {
      for (var i = 0; i < 14; i++) {
        final speed = 0.5 + _r(i + 700) * 0.6;
        final y = ((_r(i + 800) + t * speed) % 1.0) * h;
        final x = (_r(i + 900) * w + math.sin((t * 3 + _r(i)) * math.pi * 2) * 12 + y * 0.15 * sway) % w;
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate((t * 6 + i) * math.pi);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 6, height: 3.2),
            Paint()..color = _c(i.isEven ? const Color(0xFFC9772E) : const Color(0xFF9A5A2A), 0.55));
        canvas.restore();
      }
    }
    if (season.snow) {
      for (var i = 0; i < 30; i++) {
        final y = ((_r(i + 1000) + t * (0.3 + _r(i + 1100) * 0.4)) % 1.0) * h;
        final x = _r(i + 1200) * w + math.sin((t * 4 + _r(i)) * math.pi * 2) * 6;
        canvas.drawCircle(Offset(x, y), 1 + _r(i + 1300) * 1.4, Paint()..color = _c(Colors.white, 0.45));
      }
    }
    if (season.summer && !season.heather) {
      // Een paar vlinders/insecten die boven de wei dansen.
      for (var i = 0; i < 4; i++) {
        final x = (_r(i + 1400) + t * 0.2 * (i.isEven ? 1 : -1)) % 1.0 * w;
        final y = h * 0.78 + math.sin((t * 6 + i) * math.pi) * 8;
        canvas.drawCircle(Offset(x, y), 1.5, Paint()..color = _c(const Color(0xFFF2C14E), 0.5));
      }
    }
  }

  @override
  bool shouldRepaint(covariant LandscapePainter old) =>
      old.t != t || old.tilt != tilt || old.season.month != season.month || old.opacity != opacity || old.ink != ink;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../domain/run_helpers.dart' show sunTimes;

/// Zonneboog: de baan van de zon van op- tot ondergang, met nu (zon) en je loopmoment (gouden stuk).
/// Valt je run (deels) in het donker, dan zie je dat meteen op de lijn eronder.
class SunArc extends StatelessWidget {
  const SunArc({super.key, required this.start, required this.minutes, required this.lat, required this.lon, this.height = 74});
  final DateTime start;
  final int minutes;
  final double lat, lon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final st = sunTimes(start, lat, lon);
    final rise = st.sunrise, set = st.sunset;
    if (rise == null || set == null) return const SizedBox.shrink();
    final end = start.add(Duration(minutes: minutes));
    final dark = start.isBefore(rise) || end.isAfter(set);
    final label = trf('Zon op {op} · onder {onder}', {'op': Fmt.time(rise), 'onder': Fmt.time(set)});
    return Semantics(
      label: dark ? '$label. ${tr('Je loopt deels in het donker.')}' : label,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SunArcPainter(
            rise: rise,
            set: set,
            start: start,
            end: end,
            now: DateTime.now(),
            line: RwColors.subtle,
            accent: RwColors.accent,
            sun: const Color(0xFFFFB547),
            text: RwColors.subtle,
            riseLabel: Fmt.time(rise),
            setLabel: Fmt.time(set),
            textScale: MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4),
          ),
        ),
      ),
    );
  }
}

class _SunArcPainter extends CustomPainter {
  _SunArcPainter({
    required this.rise,
    required this.set,
    required this.start,
    required this.end,
    required this.now,
    required this.line,
    required this.accent,
    required this.sun,
    required this.text,
    required this.riseLabel,
    required this.setLabel,
    required this.textScale,
  });

  final DateTime rise, set, start, end, now;
  final Color line, accent, sun, text;
  final String riseLabel, setLabel;
  final double textScale;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fontSize = 10.5 * textScale;
    final baseY = h - fontSize - 6;
    final left = w * 0.14, right = w * 0.86;
    final arcH = baseY - 6;
    // Buiten zon op/onder: 3 uur extra lijn aan beide kanten.
    final t0 = rise.subtract(const Duration(hours: 3)), t1 = set.add(const Duration(hours: 3));

    double xOf(DateTime t) {
      if (t.isBefore(rise)) {
        final f = t.difference(t0).inSeconds / rise.difference(t0).inSeconds;
        return f.clamp(0.0, 1.0) * left;
      }
      if (t.isAfter(set)) {
        final f = t.difference(set).inSeconds / t1.difference(set).inSeconds;
        return right + f.clamp(0.0, 1.0) * (w - right);
      }
      final f = t.difference(rise).inSeconds / set.difference(rise).inSeconds;
      return left + f * (right - left);
    }

    Offset at(DateTime t) {
      final x = xOf(t);
      if (x <= left || x >= right) return Offset(x, baseY);
      final f = (x - left) / (right - left);
      return Offset(x, baseY - math.sin(f * math.pi) * arcH);
    }

    // Horizon en donkere stukken.
    final horizon = Paint()
      ..color = line.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(0, baseY), Offset(w, baseY), horizon);
    final night = Paint()
      ..color = line.withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(2, baseY), Offset(left, baseY), night);
    canvas.drawLine(Offset(right, baseY), Offset(w - 2, baseY), night);

    // De boog (gestippeld).
    final arc = Path();
    for (var i = 0; i <= 60; i++) {
      final f = i / 60;
      final p = Offset(left + f * (right - left), baseY - math.sin(f * math.pi) * arcH);
      i == 0 ? arc.moveTo(p.dx, p.dy) : arc.lineTo(p.dx, p.dy);
    }
    final dots = Paint()
      ..color = line.withValues(alpha: 0.5)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final m = arc.computeMetrics().first;
    for (var d = 0.0; d < m.length; d += 7) {
      canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), dots);
    }

    // Je run: een gouden stuk van de baan.
    final run = Path();
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final t = start.add(Duration(seconds: (end.difference(start).inSeconds * i / steps).round()));
      final p = at(t);
      i == 0 ? run.moveTo(p.dx, p.dy) : run.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        run,
        Paint()
          ..color = accent
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke);
    final sp = at(start);
    canvas.drawCircle(sp, 5.5, Paint()..color = accent);
    canvas.drawCircle(sp, 2.5, Paint()..color = Colors.white);

    // De zon nu (als het licht is).
    if (now.isAfter(rise) && now.isBefore(set)) {
      final p = at(now);
      canvas.drawCircle(p, 11, Paint()..shader = RadialGradient(colors: [sun.withValues(alpha: 0.45), sun.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: p, radius: 11)));
      canvas.drawCircle(p, 5, Paint()..color = sun);
    }

    // Tijden onder zon op en zon onder.
    void label(String s, double x) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: text, fontSize: fontSize, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((x - tp.width / 2).clamp(0, w - tp.width), baseY + 4));
    }

    label('↑ $riseLabel', left);
    label('↓ $setLabel', right);
  }

  @override
  bool shouldRepaint(covariant _SunArcPainter old) =>
      old.start != start || old.end != end || old.rise != rise || old.line != line || old.textScale != textScale;
}

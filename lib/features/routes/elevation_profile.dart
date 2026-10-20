import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/route_geometry.dart';

/// Hoogteprofiel van een route. Sleep met je vinger over het profiel om
/// te zien waar je op de kaart bent ([highlight] = 0 bij start, 1 bij finish).
class ElevationProfileChart extends StatefulWidget {
  const ElevationProfileChart({
    super.key,
    required this.profile,
    this.highlight,
    this.height = 120,
  });

  final List<ElevationSample> profile;
  final ValueNotifier<double?>? highlight;
  final double height;

  @override
  State<ElevationProfileChart> createState() => _ElevationProfileChartState();
}

class _ElevationProfileChartState extends State<ElevationProfileChart> {
  double? _fraction;

  static const _leftAxis = 34.0;

  void _update(Offset local, double width) {
    final usable = width - _leftAxis;
    if (usable <= 0) return;
    final f = ((local.dx - _leftAxis) / usable).clamp(0.0, 1.0);
    setState(() => _fraction = f);
    widget.highlight?.value = f;
  }

  void _clear() {
    setState(() => _fraction = null);
    widget.highlight?.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    if (p.length < 3) return const SizedBox.shrink();
    final range = elevationRange(p);
    final ascent = profileAscent(p);
    final total = p.last.meters;
    final f = _fraction;
    final atMeters = f == null ? null : f * total;
    final atEle = atMeters == null ? null : elevationAt(p, atMeters);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _Stat(icon: Icons.trending_up, text: '${ascent.round()} m omhoog'),
            _Stat(icon: Icons.vertical_align_top, text: 'hoogste ${range.max.round()} m'),
            _Stat(icon: Icons.vertical_align_bottom, text: 'laagste ${range.min.round()} m'),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _update(d.localPosition, c.maxWidth),
            onTapUp: (_) => _clear(),
            onHorizontalDragStart: (d) => _update(d.localPosition, c.maxWidth),
            onHorizontalDragUpdate: (d) => _update(d.localPosition, c.maxWidth),
            onHorizontalDragEnd: (_) => _clear(),
            onHorizontalDragCancel: _clear,
            child: SizedBox(
              height: widget.height,
              width: c.maxWidth,
              // Voor schermlezers: een samenvatting in plaats van de grafiek.
              child: Semantics(
                label: 'Hoogteprofiel: ${ascent.round()} meter omhoog, hoogste punt ${range.max.round()} meter, laagste ${range.min.round()} meter.',
                excludeSemantics: true,
              child: CustomPaint(
                painter: _ProfilePainter(p, range.min, range.max, f, _leftAxis),
              ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          atMeters == null
              ? (range.max - range.min < 8
                  ? 'Vrijwel vlak: maar ${(range.max - range.min).round()} m verschil. Sleep over het profiel om mee te kijken op de kaart.'
                  : 'Sleep over het profiel om mee te kijken op de kaart.')
              : '${Fmt.km(atMeters, decimals: 1)} · ${atEle!.round()} m hoog',
          style: TextStyle(
            color: atMeters == null ? RwColors.subtle : RwColors.text,
            fontSize: 12,
            fontWeight: atMeters == null ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: RwColors.accent),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12.5, color: RwColors.muted)),
        ],
      );
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter(this.profile, this.minEle, this.maxEle, this.fraction, this.leftAxis);

  final List<ElevationSample> profile;
  final double minEle;
  final double maxEle;
  final double? fraction;
  final double leftAxis;

  @override
  void paint(Canvas canvas, Size size) {
    final total = profile.last.meters;
    if (total <= 0) return;

    // Minstens 20 m bereik, zodat een vlak rondje er ook vlak uitziet.
    final span = math.max(20.0, maxEle - minEle);
    final mid = (maxEle + minEle) / 2;
    final lo = mid - span / 2 - span * 0.08;
    final hi = mid + span / 2 + span * 0.12;

    const bottomAxis = 16.0;
    final chart = Rect.fromLTRB(leftAxis, 4, size.width, size.height - bottomAxis);
    double x(double m) => chart.left + m / total * chart.width;
    double y(double e) => chart.bottom - (e - lo) / (hi - lo) * chart.height;

    // Rasterlijnen en hoogtelabels.
    final grid = Paint()
      ..color = RwColors.border
      ..strokeWidth = 1;
    for (final e in [minEle, maxEle]) {
      final yy = y(e);
      canvas.drawLine(Offset(chart.left, yy), Offset(chart.right, yy), grid);
      _text(canvas, '${e.round()} m', Offset(0, yy - 6), RwColors.subtle, 10);
    }

    // Kilometerlabels onderaan.
    final kmStep = total <= 6000 ? 1000.0 : total <= 15000 ? 2000.0 : 5000.0;
    for (var m = 0.0; m <= total + 1; m += kmStep) {
      final label = '${(m / 1000).round()}';
      _text(canvas, label, Offset(x(m) - 3, chart.bottom + 3), RwColors.subtle, 10);
    }
    _text(canvas, 'km', Offset(chart.right - 14, chart.bottom + 3), RwColors.subtle, 10);

    // Vlak met verloop en de lijn.
    final line = Path()..moveTo(x(profile.first.meters), y(profile.first.ele));
    for (final s in profile.skip(1)) {
      line.lineTo(x(s.meters), y(s.ele));
    }
    final area = Path.from(line)
      ..lineTo(x(profile.last.meters), chart.bottom)
      ..lineTo(x(profile.first.meters), chart.bottom)
      ..close();
    // Effen vlak (geen kleurverloop): sommige Samsung-toestellen tekenen een verloop-shader niet.
    canvas.drawPath(area, Paint()..color = RwColors.accent.withValues(alpha: 0.22));
    canvas.drawPath(
      line,
      Paint()
        ..color = RwColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );

    // Waar je vinger is.
    final f = fraction;
    if (f != null) {
      final m = f * total;
      final e = elevationAt(profile, m) ?? minEle;
      final px = x(m);
      canvas.drawLine(
        Offset(px, chart.top),
        Offset(px, chart.bottom),
        Paint()
          ..color = RwColors.text.withValues(alpha: 0.6)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(Offset(px, y(e)), 6, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(px, y(e)),
        6,
        Paint()
          ..color = RwColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  void _text(Canvas canvas, String s, Offset at, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: RwFonts.body, color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _ProfilePainter old) =>
      old.fraction != fraction || old.profile != profile || old.minEle != minEle || old.maxEle != maxEle;
}

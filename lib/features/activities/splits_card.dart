import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/best_efforts.dart';
import '../../domain/route_geometry.dart';
import '../../domain/run_streams.dart';
import '../../shared/widgets.dart';
import '../routes/route_map.dart' show windColor;

/// Tijden per kilometer en een grafiek van tempo, hoogte en hartslag (runs uit Strava).
class SplitsCard extends ConsumerWidget {
  const SplitsCard({super.key, required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = activity;
    final async = ref.watch(activityStreamsProvider(a.id!));
    return RwCard(
      title: 'PER KILOMETER',
      child: async.when(
        loading: () => const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Tijden per km laden…', style: TextStyle(color: RwColors.muted)),
          ],
        ),
        error: (e, _) => Row(
          children: [
            Expanded(child: Text(friendlyError(e), style: const TextStyle(color: RwColors.muted))),
            TextButton(onPressed: () => ref.invalidate(activityStreamsProvider(a.id!)), child: const Text('Opnieuw')),
          ],
        ),
        data: (json) {
          final s = RunStreams.fromJson(json);
          if (s == null) {
            return const Text('Voor deze run zijn geen tijden per km beschikbaar.', style: TextStyle(color: RwColors.muted));
          }
          final splits = splitsOf(s);
          final ex = extremes(splits);
          final hasHr = splits.any((x) => x.heartRate != null);
          final hasEle = splits.any((x) => x.elevationGain != null);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 150, child: _RunChart(streams: s)),
              const SizedBox(height: 6),
              Row(
                children: [
                  _legend(RwColors.accent, 'tempo'),
                  if (s.altitude != null) _legend(RwColors.bar, 'hoogte'),
                  if (s.heartRate != null) _legend(RwColors.danger, 'hartslag'),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const SizedBox(width: 44, child: Text('km', style: _head)),
                  const Expanded(child: Text('tempo', style: _head)),
                  if (hasHr) const SizedBox(width: 52, child: Text('hart', style: _head, textAlign: TextAlign.right)),
                  if (hasEle) const SizedBox(width: 52, child: Text('omhoog', style: _head, textAlign: TextAlign.right)),
                  const SizedBox(width: 72, child: Text('wind', style: _head, textAlign: TextAlign.right)),
                ],
              ),
              const Divider(height: 12),
              for (final sp in splits) _row(sp, ex, hasHr, hasEle),
              const SizedBox(height: 6),
              Text('${a.source == 'strava' ? 'Gegevens via Strava' : 'Opgenomen met RunWise'}. Wind = het weer bij de start van je run.',
                  style: const TextStyle(color: RwColors.subtle, fontSize: 11)),
              ..._efforts(s, ref),
            ],
          );
        },
      ),
    );
  }

  /// Snelste stukken binnen deze run, met een kroontje als het je snelste ooit is.
  List<Widget> _efforts(RunStreams s, WidgetRef ref) {
    final list = bestEfforts(s);
    if (list.isEmpty) return const [];
    final all = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final overall = bestOverall([
      for (final x in all)
        if (x.id != null && x.bestEfforts != null && x.id != activity.id) (id: x.id!, efforts: x.bestEfforts!),
    ]);
    return [
      const Divider(height: 28),
      const Text('SNELSTE STUKKEN', style: _head),
      const SizedBox(height: 8),
      for (final b in list)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 110, child: Text(b.label, style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(child: Text(Fmt.duration(b.seconds), style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(Fmt.pace(b.paceSecPerKm), style: const TextStyle(color: RwColors.muted)),
              if ((overall[b.meters.round()]?.seconds ?? double.infinity) > b.seconds + 0.5) ...[
                const SizedBox(width: 8),
                const Tooltip(
                  message: 'Je snelste ooit op deze afstand',
                  child: Icon(Icons.emoji_events, color: RwColors.accent, size: 18),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  static const _head = TextStyle(color: RwColors.subtle, fontSize: 12, fontWeight: FontWeight.w600);

  Widget _legend(Color c, String label) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 4, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: RwColors.subtle, fontSize: 11)),
        ]),
      );

  Widget _row(KmSplit sp, ({KmSplit? fastest, KmSplit? slowest}) ex, bool hasHr, bool hasEle) {
    final a = activity;
    final cls = sp.bearing == null || a.windDirectionDegrees == null || a.windSpeedKmh == null
        ? null
        : classifyWind(sp.bearing!, a.windSpeedKmh!, a.windDirectionDegrees!);
    final windText = switch (cls) {
      WindClass.head => 'tegen',
      WindClass.tail => 'mee',
      WindClass.side => 'zij',
      WindClass.calm => 'rustig',
      null => '',
    };
    final isFast = identical(sp, ex.fastest), isSlow = identical(sp, ex.slowest);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              sp.partial ? (sp.meters / 1000).toStringAsFixed(2).replaceAll('.', ',') : '${sp.index}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Row(children: [
              Text(Fmt.pace(sp.paceSecPerKm).replaceAll(' /km', ''),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isFast ? RwColors.good : (isSlow ? RwColors.warning : RwColors.text),
                  )),
              if (isFast) const Text('  snelst', style: TextStyle(color: RwColors.good, fontSize: 12)),
            ]),
          ),
          if (hasHr)
            SizedBox(
              width: 52,
              child: Text(sp.heartRate == null ? '–' : '${sp.heartRate!.round()}',
                  textAlign: TextAlign.right, style: const TextStyle(color: RwColors.muted)),
            ),
          if (hasEle)
            SizedBox(
              width: 52,
              child: Text(sp.elevationGain == null ? '–' : '${sp.elevationGain!.round()} m',
                  textAlign: TextAlign.right, style: const TextStyle(color: RwColors.muted)),
            ),
          SizedBox(
            width: 72,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (cls != null && cls != WindClass.calm)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(color: windColor(cls), shape: BoxShape.circle),
                  ),
                Text(windText, style: const TextStyle(color: RwColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tempo (oranje, sneller = hoger), hoogte (grijs vlak) en hartslag (rood).
class _RunChart extends StatelessWidget {
  const _RunChart({required this.streams});
  final RunStreams streams;

  @override
  Widget build(BuildContext context) {
    final pace = paceSeries(streams);
    final km = (streams.totalDistance / 1000).toStringAsFixed(1).replaceAll('.', ',');
    return Semantics(
      label: 'Grafiek van tempo${streams.altitude != null ? ', hoogte' : ''}${streams.heartRate != null ? ' en hartslag' : ''} over $km kilometer.',
      excludeSemantics: true,
      child: CustomPaint(painter: _ChartPainter(streams, pace), size: Size.infinite),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.s, this.pace);
  final RunStreams s;
  final List<({double meters, double pace})> pace;

  @override
  void paint(Canvas canvas, Size size) {
    final total = s.totalDistance;
    if (total <= 0) return;
    const bottomAxis = 14.0;
    final h = size.height - bottomAxis;
    double x(double m) => m / total * size.width;

    // Hoogte als vlak.
    final alt = s.altitude;
    if (alt != null) {
      final r = rangeOf(alt);
      final span = (r.max - r.min).clamp(15, double.infinity);
      final path = Path()..moveTo(0, h);
      for (var i = 0; i < s.length; i++) {
        path.lineTo(x(s.distance[i]), h - (alt[i] - r.min) / span * h * 0.45);
      }
      path
        ..lineTo(size.width, h)
        ..close();
      canvas.drawPath(path, Paint()..color = RwColors.bar);
    }

    // Hartslag.
    final hr = s.heartRate;
    if (hr != null) {
      final valid = hr.where((v) => v > 30);
      if (valid.isNotEmpty) {
        final r = rangeOf(valid);
        final span = (r.max - r.min).clamp(10, double.infinity);
        final path = Path();
        var started = false;
        for (var i = 0; i < s.length; i++) {
          if (hr[i] <= 30) continue;
          final p = Offset(x(s.distance[i]), h - 6 - (hr[i] - r.min) / span * (h - 12));
          started ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
          started = true;
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = RwColors.danger.withValues(alpha: 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // Tempo: sneller = hoger.
    if (pace.length >= 2) {
      final r = rangeOf(pace.map((p) => p.pace));
      final span = (r.max - r.min).clamp(20, double.infinity);
      final path = Path();
      for (var i = 0; i < pace.length; i++) {
        final p = Offset(x(pace[i].meters), 6 + (pace[i].pace - r.min) / span * (h - 12));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = RwColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Kilometerstreepjes.
    final kmStep = total <= 8000 ? 1000.0 : total <= 21000 ? 5000.0 : 10000.0;
    for (var m = kmStep; m < total; m += kmStep) {
      final tp = TextPainter(
        text: TextSpan(text: '${(m / 1000).round()}', style: const TextStyle(color: RwColors.subtle, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x(m) - tp.width / 2, h + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.s != s;
}

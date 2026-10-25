import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/route_geometry.dart';
import '../../domain/run_streams.dart';
import '../../shared/widgets.dart';
import '../routes/elevation_profile.dart';

/// Hoogteprofiel van een gelopen run, met een tabel: stijgen, dalen, hoogste en laagste punt,
/// en per kilometer hoeveel je omhoog en omlaag ging.
class ElevationCard extends ConsumerWidget {
  const ElevationCard({super.key, required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = activity.id;
    if (id == null) return const SizedBox.shrink();
    final json = ref.watch(activityStreamsProvider(id)).value;
    final s = json == null ? null : RunStreams.fromJson(json);
    final alt = s?.altitude;
    if (s == null || alt == null || alt.length < 3 || s.distance.length != alt.length) return const SizedBox.shrink();

    // Licht gladstrijken (GPS-hoogte springt) en terugbrengen tot ~250 punten.
    final step = (alt.length / 250).ceil().clamp(1, 1 << 20);
    final profile = <ElevationSample>[];
    for (var i = 0; i < alt.length; i += step) {
      var sum = 0.0, n = 0;
      for (var j = (i - 2).clamp(0, alt.length - 1); j <= (i + 2).clamp(0, alt.length - 1); j++) {
        sum += alt[j];
        n++;
      }
      profile.add(ElevationSample(s.distance[i], sum / n));
    }
    if (profile.last.meters < s.distance.last) profile.add(ElevationSample(s.distance.last, alt.last));

    // Stijgen/dalen met een drempel van 1 m, zodat ruis niet optelt.
    double up = 0, down = 0;
    var ref0 = profile.first.ele;
    for (final p in profile) {
      final d = p.ele - ref0;
      if (d >= 1) {
        up += d;
        ref0 = p.ele;
      } else if (d <= -1) {
        down -= d;
        ref0 = p.ele;
      }
    }
    final range = elevationRange(profile);

    // Per kilometer.
    final perKm = <({int km, double up, double down})>[];
    var kmUp = 0.0, kmDown = 0.0, km = 1;
    var last = profile.first.ele;
    for (final p in profile) {
      while (p.meters >= km * 1000) {
        perKm.add((km: km, up: kmUp, down: kmDown));
        kmUp = 0;
        kmDown = 0;
        km++;
      }
      final d = p.ele - last;
      if (d.abs() >= 1) {
        d > 0 ? kmUp += d : kmDown -= d;
        last = p.ele;
      }
    }
    if (kmUp > 0 || kmDown > 0 || perKm.isEmpty) perKm.add((km: km, up: kmUp, down: kmDown));

    final flat = up < 5 && down < 5;
    return RwCard(
      title: 'HOOGTEPROFIEL',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ElevationProfileChart(profile: profile, height: 110),
        const SizedBox(height: 12),
        Table(
          columnWidths: const {0: FlexColumnWidth(), 1: FlexColumnWidth(), 2: FlexColumnWidth(), 3: FlexColumnWidth()},
          children: [
            TableRow(children: [
              for (final l in ['Stijgen', 'Dalen', 'Hoogste', 'Laagste'])
                Text(l, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
            ]),
            TableRow(children: [
              for (final v in ['${up.round()} m', '${down.round()} m', '${range.max.round()} m', '${range.min.round()} m'])
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(v, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: 18)),
                ),
            ]),
          ],
        ),
        if (flat) ...[
          const SizedBox(height: 10),
          Text('Vlak parcours: minder dan 5 meter klimmen.', style: TextStyle(color: RwColors.muted)),
        ] else if (perKm.length > 1) ...[
          const SizedBox(height: 14),
          Text('PER KILOMETER', style: RwText.overline),
          const SizedBox(height: 6),
          Table(
            columnWidths: const {0: FixedColumnWidth(52), 1: FlexColumnWidth(), 2: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [
                Text('km', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
                Text('omhoog', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
                Text('omlaag', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
              ]),
              for (final k in perKm)
                TableRow(children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${k.km}', style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(k.up < 1 ? '–' : '+${k.up.round()} m',
                      style: TextStyle(color: k.up >= 10 ? RwColors.warning : RwColors.text, fontFeatures: rwTnum, fontWeight: FontWeight.w600)),
                  Text(k.down < 1 ? '–' : '−${k.down.round()} m', style: TextStyle(color: RwColors.muted, fontFeatures: rwTnum)),
                ]),
            ],
          ),
        ],
      ]),
    );
  }
}

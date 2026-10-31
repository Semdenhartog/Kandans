import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../data/services/age_grade_service.dart';
import '../../domain/age_grading.dart';
import '../../domain/records.dart';
import '../../shared/widgets.dart';
import 'activity_providers.dart';

/// Je records per afstand: echt gelopen én gecorrigeerd voor het weer.
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(recordsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mijn records')),
      body: records.isEmpty
          ? const EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'Nog geen records',
              message: 'Loop een run van 5 km of meer. Kadans houdt dan je snelste tijden bij, ook gecorrigeerd voor het weer.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  'Naast je echte tijd zie je je weer-record: de tijd die je bij ideaal loopweer (10 °C, windstil) zou hebben gelopen. '
                  'Zo telt een snelle run in storm ook mee.',
                  style: TextStyle(color: RwColors.muted, height: 1.45),
                ),
                const SizedBox(height: 14),
                _AgeGradeCard(records: records.distances),
                const SizedBox(height: 10),
                for (final r in records.distances) ...[
                  _RecordCard(record: r),
                  const SizedBox(height: 10),
                ],
                if (records.longest != null)
                  RwCard(
                    title: 'LANGSTE RUN',
                    onTap: records.longest!.id == null ? null : () => context.go('/runs/${records.longest!.id}'),
                    child: Text(
                      '${Fmt.km(records.longest!.distanceMeters, decimals: 1)} · ${Fmt.date(records.longest!.startedAt)}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});
  final DistanceRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return RwCard(
      title: '${r.distance.label.toUpperCase()} · ${r.count} ${r.count == 1 ? 'RUN' : 'RUNS'}',
      child: Row(
        children: [
          Expanded(
            child: _Cell(
              label: 'Snelste tijd',
              value: Fmt.duration(r.bestSeconds),
              sub: Fmt.date(r.best.startedAt),
              color: RwColors.accent,
              onTap: r.best.id == null ? null : () => context.go('/runs/${r.best.id}'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Cell(
              label: 'Weer-record',
              value: Fmt.duration(r.bestWeatherSeconds),
              sub: r.weatherRecordDiffers ? Fmt.date(r.bestWeather.startedAt) : 'zelfde run',
              color: RwColors.good,
              onTap: r.bestWeather.id == null ? null : () => context.go('/runs/${r.bestWeather.id}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, required this.sub, required this.color, this.onTap});
  final String label;
  final String value;
  final String sub;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: RwColors.surfaceHigh, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: RwColors.subtle)),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 24, fontWeight: FontWeight.w800, color: color)),
              Text(sub, style: TextStyle(fontSize: 12, color: RwColors.muted)),
            ],
          ),
        ),
      );
}

/// Leeftijdsniveau: je beste tijden vergeleken met de wereldtop voor jouw leeftijd.
class _AgeGradeCard extends ConsumerWidget {
  const _AgeGradeCard({required this.records});
  final List<DistanceRecord> records;

  Future<void> _setup(BuildContext context, WidgetRef ref, AgeGradeSettings cur) async {
    var year = cur.birthYear ?? 1990;
    var sex = cur.sex ?? Sex.male;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Leeftijdsniveau instellen')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Geboortejaar'), style: const TextStyle(fontWeight: FontWeight.w600)),
            Row(children: [
              IconButton(onPressed: () => set(() => year--), icon: const Icon(Icons.remove_circle_outline)),
              Text('$year', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              IconButton(onPressed: () => set(() => year++), icon: const Icon(Icons.add_circle_outline)),
            ]),
            const SizedBox(height: 8),
            SegmentedButton<Sex>(
              segments: [
                ButtonSegment(value: Sex.male, label: Text(tr('Man'))),
                ButtonSegment(value: Sex.female, label: Text(tr('Vrouw'))),
              ],
              selected: {sex},
              onSelectionChanged: (v) => set(() => sex = v.first),
            ),
            const SizedBox(height: 8),
            Text(tr('De wereldnormen verschillen per leeftijd en geslacht. Blijft op je telefoon.'),
                style: TextStyle(color: RwColors.subtle, fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Bewaren'))),
          ],
        ),
      ),
    );
    if (ok == true) await saveAgeGradeSettings(ref, year.clamp(1920, DateTime.now().year - 8), sex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(ageGradeSettingsProvider).value ?? const AgeGradeSettings();
    if (!st.ready) {
      return RwCard(
        title: tr('LEEFTIJDSNIVEAU'),
        onTap: () => _setup(context, ref, st),
        child: Text(
          tr('Hoe goed zijn je tijden voor jouw leeftijd? Vul je geboortejaar in en vergelijk eerlijk met de wereldtop, ook door de jaren heen.'),
          style: const TextStyle(height: 1.45),
        ),
      );
    }
    final rows = <(String, double)>[];
    for (final r in records) {
      final pct = ageGradePercent(sex: st.sex!, age: st.ageAt(r.best.startedAt), meters: r.distance.meters, seconds: r.bestSeconds.toDouble());
      if (pct != null) rows.add((r.distance.label, pct));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final top = rows.reduce((a, b) => b.$2 > a.$2 ? b : a);
    return RwCard(
      title: tr('LEEFTIJDSNIVEAU'),
      onTap: () => _setup(context, ref, st),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${top.$2.toStringAsFixed(1).replaceAll('.', ',')}%',
              style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 34, fontWeight: FontWeight.w800, color: RwColors.accent)),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${tr(ageGradeLevel(top.$2))} · ${top.$1}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        for (final (label, pct) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(width: 120, child: Text(label)),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: (pct / 100).clamp(0.0, 1.0), minHeight: 6, backgroundColor: RwColors.surfaceHigh),
                ),
              ),
              SizedBox(width: 56, child: Text('${pct.round()}%', textAlign: TextAlign.right, style: TextStyle(color: RwColors.muted))),
            ]),
          ),
        const SizedBox(height: 6),
        Text(tr('100% = wereldrecordniveau voor je leeftijd. 60% is lokaal sterk, 70% regionaal, 80% nationaal. Benadering van de WMA-normen.'),
            style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.35)),
      ]),
    );
  }
}

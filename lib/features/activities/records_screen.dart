import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
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
              message: 'Loop een run van 5 km of meer. RunWise houdt dan je snelste tijden bij, ook gecorrigeerd voor het weer.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const Text(
                  'Naast je echte tijd zie je je weer-record: de tijd die je bij ideaal loopweer (10 °C, windstil) zou hebben gelopen. '
                  'Zo telt een snelle run in storm ook mee.',
                  style: TextStyle(color: RwColors.muted, height: 1.45),
                ),
                const SizedBox(height: 14),
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
              Text(label, style: const TextStyle(fontSize: 12, color: RwColors.subtle)),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 24, fontWeight: FontWeight.w800, color: color)),
              Text(sub, style: const TextStyle(fontSize: 12, color: RwColors.muted)),
            ],
          ),
        ),
      );
}

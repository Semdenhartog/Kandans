import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/segment_store.dart';
import '../../domain/run_streams.dart';
import '../../domain/segments.dart';
import '../../shared/widgets.dart';

void openSegments(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SegmentsScreen()));

String segName(Segment s) => segmentLabel(s, (h) => Fmt.compass(h));

/// Mijn stukken: vaste stukken uit je eigen runs, met je beste tijd per stuk.
class SegmentsScreen extends ConsumerStatefulWidget {
  const SegmentsScreen({super.key});

  @override
  ConsumerState<SegmentsScreen> createState() => _SegmentsScreenState();
}

class _SegmentsScreenState extends ConsumerState<SegmentsScreen> {
  double? _progress;

  Future<void> _scan() async {
    setState(() => _progress = 0);
    try {
      final List<Activity> runs = ref.read(activitiesProvider).value ?? await ref.read(activitiesProvider.future) ?? const [];
      await SegmentStore.scan(ref.read(repositoryProvider), runs, progress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      ref.invalidate(segmentStateProvider);
    } catch (e) {
      if (mounted) showMessage(context, tr('Zoeken lukte niet. Probeer het later opnieuw.'), error: true);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _rename(Segment s) async {
    final c = TextEditingController(text: s.name ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Naam van dit stuk')),
        content: TextField(controller: c, autofocus: true, maxLength: 40, decoration: InputDecoration(hintText: tr('Bijvoorbeeld: De dijk'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Bewaren'))),
        ],
      ),
    );
    if (v == null) return;
    await SegmentStore.rename(s.id, v);
    ref.invalidate(segmentStateProvider);
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(segmentStateProvider).value;
    final busy = _progress != null;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Mijn stukken'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr('Stukken die je vaak loopt, zoals de dijk of de bosweg, herkent Kadans vanzelf uit je eigen opnames. Per stuk zie je je beste tijd; na elke run zie je of je sneller was.'),
            style: TextStyle(color: RwColors.muted, height: 1.45),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : _scan,
            icon: busy
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, value: _progress, color: RwColors.accentDark))
                : const Icon(Icons.manage_search),
            label: Text(busy ? tr('Runs bekijken…') : (st?.segments.isEmpty ?? true) ? tr('Zoek mijn stukken') : tr('Opnieuw zoeken')),
          ),
          if (st?.scannedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(trf('Laatst gezocht: {datum}', {'datum': Fmt.date(st!.scannedAt!)}),
                  textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          if (st != null && st.segments.isEmpty && st.scannedAt != null)
            RwCard(child: Text(tr('Nog geen vaste stukken gevonden. Daarvoor moet je een stuk minstens 3 keer met Kadans hebben gelopen.'))),
          for (final s in st?.segments ?? const <Segment>[]) ...[
            _SegmentCard(seg: s, best: st!.bests[s.id], onRename: () => _rename(s)),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _SegmentCard extends StatelessWidget {
  const _SegmentCard({required this.seg, required this.best, required this.onRename});
  final Segment seg;
  final SegmentBest? best;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final b = best;
    return RwCard(
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, color: RwColors.accent.withValues(alpha: 0.15)),
          child: Icon(Icons.timeline, color: RwColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(segName(seg), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              b == null
                  ? Fmt.km(seg.length, decimals: 1)
                  : trf('Record {tijd} ({tempo}) · {n}× gelopen', {
                      'tijd': Fmt.duration(b.seconds.round()),
                      'tempo': Fmt.pace(b.seconds / (seg.length / 1000)),
                      'n': b.efforts,
                    }),
              style: TextStyle(color: RwColors.muted, fontSize: 13),
            ),
          ]),
        ),
        IconButton(tooltip: tr('Naam geven'), icon: const Icon(Icons.edit_outlined), onPressed: onRename),
        if (b != null)
          IconButton(tooltip: tr('Run met het record'), icon: const Icon(Icons.chevron_right), onPressed: () => context.go('/runs/${b.runId}')),
      ]),
    );
  }
}

/// In het rundetail: je tijden op je vaste stukken in deze run, met een record-ster.
class SegmentEffortsCard extends ConsumerWidget {
  const SegmentEffortsCard({super.key, required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = activity.id;
    if (id == null) return const SizedBox.shrink();
    final json = ref.watch(activityStreamsProvider(id)).value;
    final st = RunStreams.fromJson(json);
    if (st == null || st.positions == null) return const SizedBox.shrink();
    return FutureBuilder(
      future: SegmentStore.effortsFor(activity, st),
      builder: (context, snap) {
        final list = snap.data ?? const [];
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: RwCard(
            title: tr('JE STUKKEN'),
            onTap: () => openSegments(context),
            child: Column(children: [
              for (final e in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Icon(e.record ? Icons.star_rounded : Icons.timeline, size: 20, color: e.record ? RwColors.accent : RwColors.subtle),
                    const SizedBox(width: 10),
                    Expanded(child: Text(segName(e.seg), style: const TextStyle(fontWeight: FontWeight.w600))),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(Fmt.duration(e.seconds.round()), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: rwTnum)),
                      Text(
                        e.record
                            ? tr('Nieuw record!')
                            : e.best == null
                                ? ''
                                : trf('record {tijd}', {'tijd': Fmt.duration(e.best!.seconds.round())}),
                        style: TextStyle(color: e.record ? RwColors.accent : RwColors.subtle, fontSize: 12),
                      ),
                    ]),
                  ]),
                ),
            ]),
          ),
        );
      },
    );
  }
}

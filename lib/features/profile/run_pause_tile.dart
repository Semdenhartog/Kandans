import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/run_pause_store.dart';
import '../../domain/run_pause.dart';
import '../../shared/widgets.dart';
import '../dashboard/dashboard_providers.dart';

/// Instelling in Ik: pauze nemen bij blessure, ziekte of vakantie.
class RunPauseTile extends ConsumerWidget {
  const RunPauseTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(currentPauseProvider);
    return ListTile(
      leading: Icon(p == null ? Icons.pause_circle_outline : Icons.pause_circle, color: p == null ? null : RwColors.accent),
      title: Text(tr('Pauze nemen')),
      subtitle: Text(p == null ? tr('Bij blessure, ziekte of vakantie: geen herinneringen en je reeks blijft staan') : pauseLabel(p)),
      trailing: p == null ? Icon(Icons.chevron_right) : TextButton(onPressed: () => stopPause(context, ref), child: Text(tr('Weer beginnen'))),
      onTap: () => openPauseSheet(context),
    );
  }
}

/// "Blessure · tot 12 nov" of "Vakantie · tot je weer begint".
String pauseLabel(PausePeriod p) =>
    '${tr(p.reason.label)} · ${p.end == null ? tr('tot je weer begint') : trf('tot en met {datum}', {'datum': Fmt.date(p.end!)})}';

Future<void> stopPause(BuildContext context, WidgetRef ref) async {
  await ref.read(runPausesProvider.notifier).stop();
  // Herinneringen weer inplannen met de nieuwste verwachting.
  ref.invalidate(forecastProvider);
  if (context.mounted) showMessage(context, tr('Welkom terug! Begin rustig: je eerste runs mogen korter en langzamer.'));
}

Future<void> openPauseSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const PauseSheet(),
    );

/// Blad om een pauze te starten: reden en tot wanneer.
class PauseSheet extends ConsumerStatefulWidget {
  const PauseSheet({super.key});

  @override
  ConsumerState<PauseSheet> createState() => _PauseSheetState();
}

class _PauseSheetState extends ConsumerState<PauseSheet> {
  PauseReason _reason = PauseReason.injury;

  /// Aantal dagen, of null = tot ik weer begin.
  int? _days = 7;

  Future<void> _start() async {
    final now = DateTime.now();
    final until = _days == null ? null : DateTime(now.year, now.month, now.day + _days! - 1);
    await ref.read(runPausesProvider.notifier).start(_reason, until: until);
    await NotificationService.instance.cancelPlanned();
    if (!mounted) return;
    Navigator.pop(context);
    showMessage(context, tr('Pauze gestart. Geen herinneringen, en je reeks blijft staan.'));
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentPauseProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Even pauze'), style: RwText.title),
            SizedBox(height: 6),
            Text(
              tr('Tijdens een pauze krijg je geen loopherinneringen, breekt je reeks niet en weet de coach dat je herstelt.'),
              style: TextStyle(color: RwColors.muted, height: 1.4),
            ),
            if (current != null) ...[
              SizedBox(height: 12),
              Text(trf('Nu: {pauze}', {'pauze': pauseLabel(current)}), style: TextStyle(fontWeight: FontWeight.w700)),
            ],
            SizedBox(height: 16),
            Text(tr('WAAROM?'), style: RwText.overline),
            SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in PauseReason.values)
                ChoiceChip(label: Text(tr(r.label)), selected: _reason == r, onSelected: (_) => setState(() => _reason = r)),
            ]),
            SizedBox(height: 16),
            Text(tr('HOE LANG?'), style: RwText.overline),
            SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in const [3, 7, 14, 28, null])
                ChoiceChip(
                  label: Text(d == null
                      ? tr('Tot ik weer begin')
                      : d == 7
                          ? tr('1 week')
                          : d == 14
                              ? tr('2 weken')
                              : d == 28
                                  ? tr('4 weken')
                                  : trf('{n} dagen', {'n': d})),
                  selected: _days == d,
                  onSelected: (_) => setState(() => _days = d),
                ),
            ]),
            if (_reason == PauseReason.injury || _reason == PauseReason.sick) ...[
              SizedBox(height: 14),
              Text(
                tr('Twijfel je of je weer mag lopen? Vraag het een huisarts of fysiotherapeut.'),
                style: TextStyle(color: RwColors.subtle, fontSize: 12.5, height: 1.4),
              ),
            ],
            SizedBox(height: 20),
            FilledButton.icon(onPressed: _start, icon: Icon(Icons.pause), label: Text(current == null ? tr('Pauze starten') : tr('Pauze aanpassen'))),
            if (current != null) ...[
              SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await stopPause(context, ref);
                },
                child: Text(tr('Weer beginnen')),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Balk op Vandaag tijdens een pauze.
class PauseBanner extends ConsumerWidget {
  const PauseBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(currentPauseProvider);
    if (p == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: RwCard(
        padding: EdgeInsets.fromLTRB(16, 12, 8, 12),
        onTap: () => openPauseSheet(context),
        child: Row(children: [
          Icon(Icons.pause_circle, color: RwColors.accent),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trf('Pauze: {reden}', {'reden': tr(p.reason.label).toLowerCase()}), style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text(
                '${p.end == null ? tr('Geen herinneringen tot je weer begint.') : trf('Geen herinneringen tot en met {datum}.', {'datum': Fmt.date(p.end!)})} '
                '${tr('Je reeks blijft staan.')}',
                style: TextStyle(color: RwColors.muted, fontSize: 13, height: 1.35),
              ),
            ]),
          ),
          TextButton(onPressed: () => stopPause(context, ref), child: Text(tr('Weer beginnen'))),
        ]),
      ),
    );
  }
}

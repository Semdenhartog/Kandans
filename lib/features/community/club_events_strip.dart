import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/club_events_service.dart';
import '../../domain/club_calendar.dart';
import '../../shared/widgets.dart';
import 'together_screens.dart' show GroupScreen;

String _loc() => LanguageController.instance.lang.intlLocale;

/// Rij met clubevenementen bovenaan Samen → Runs: veegkaarten met een datumtegel.
class ClubEventsStrip extends ConsumerWidget {
  const ClubEventsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clubEventsProvider);
    final state = async.value;
    if (state == null) return const SizedBox.shrink(); // laden of fout: de feed niet ophouden
    final events = state.events.take(8).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: SectionLabel(tr('Clubevenementen'))),
        TextButton(
          onPressed: () => openClubEvents(context),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: Text(events.isEmpty ? tr('Agenda koppelen') : tr('Alles bekijken')),
        ),
      ]),
      SizedBox(
        height: 116,
        child: events.isEmpty
            ? _ConnectCard(onTap: () => openClubEvents(context))
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: events.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => SizedBox(
                  width: 296,
                  child: ClubEventCard(event: events[i], onTap: () => openClubEvent(context, ref, events[i])),
                ),
              ),
      ),
    ]);
  }
}

/// Lege staat: uitnodiging om een clubagenda te koppelen.
class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: RwColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RwRadius.m), side: BorderSide(color: RwColors.hairline)),
        child: InkWell(
          borderRadius: BorderRadius.circular(RwRadius.m),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.event_available_outlined, color: RwColors.accent, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr('Koppel de agenda van je loopclub of plan een groepsrun. Trainingen en wedstrijden komen dan vanzelf hier.'),
                  style: TextStyle(color: RwColors.muted, fontSize: 13.5, height: 1.35),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// Datumtegel: maand in goud, groot dagnummer, weekdag.
class DateTile extends StatelessWidget {
  const DateTile(this.date, {super.key});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final month = DateFormat('MMM', _loc()).format(date).replaceAll('.', '').toUpperCase();
    final day = DateFormat('EEE', _loc()).format(date).replaceAll('.', '').toUpperCase();
    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: RwColors.background,
        borderRadius: BorderRadius.circular(RwRadius.s),
        border: Border.all(color: RwColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      // Schaalt mee omlaag bij grote letters, zodat de tegel altijd past.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(width: 64, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: double.infinity,
          color: RwColors.accent,
          padding: const EdgeInsets.symmetric(vertical: 3),
          alignment: Alignment.center,
          child: Text(month, style: SectionLabel.style(color: const Color(0xFF1A1410)).copyWith(fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('${date.day}', style: TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 28, height: 1.1, color: RwColors.text)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(day, style: SectionLabel.style()),
        ),
      ]))),
    );
  }
}

class ClubEventCard extends StatelessWidget {
  const ClubEventCard({super.key, required this.event, this.onTap});
  final ClubEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final group = e.source == ClubEventSource.group;
    final when = e.allDay ? tr('Hele dag') : Fmt.time(e.start);
    final line2 = [when, if (e.distanceKm != null) '${e.distanceKm!.toStringAsFixed(e.distanceKm! % 1 == 0 ? 0 : 1).replaceAll('.', ',')} km', e.from].join(' · ');
    final line3 = [
      if (e.location != null) e.location!,
      if (group && (e.going ?? 0) > 0) trf('{n} gaan', {'n': '${e.going}'}),
    ].join(' · ');
    return Material(
      color: RwColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RwRadius.m), side: BorderSide(color: RwColors.hairline)),
      child: InkWell(
        borderRadius: BorderRadius.circular(RwRadius.m),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            DateTile(e.start),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w700, fontSize: 17, color: RwColors.text)),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(group ? Icons.groups_outlined : Icons.event_outlined, size: 15, color: RwColors.accent),
                  const SizedBox(width: 5),
                  Expanded(child: Text(line2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: RwColors.muted))),
                ]),
                if (line3.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(line3, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: RwColors.subtle)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Opent een evenement: groepsrun → de loopgroep; agenda-item → details.
Future<void> openClubEvent(BuildContext context, WidgetRef ref, ClubEvent e) async {
  if (e.source == ClubEventSource.group && e.groupId != null) {
    final g = ref.read(clubEventsProvider).value?.groups[e.groupId];
    if (g == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GroupScreen(group: g)));
    ref.invalidate(clubEventsProvider);
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            DateTile(e.start),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title, style: TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w700, fontSize: 20, color: RwColors.text)),
                const SizedBox(height: 2),
                Text(
                  e.allDay
                      ? '${Fmt.dateLong(e.start)} · ${tr('Hele dag')}'
                      : '${Fmt.dateLong(e.start)} · ${Fmt.time(e.start)}${e.end != null ? '–${Fmt.time(e.end!)}' : ''}',
                  style: TextStyle(color: RwColors.muted, fontSize: 13.5),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          if (e.location != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.place_outlined, size: 18, color: RwColors.accent),
                const SizedBox(width: 8),
                Expanded(child: Text(e.location!, style: TextStyle(color: RwColors.text))),
              ]),
            ),
          Row(children: [
            Icon(Icons.event_outlined, size: 18, color: RwColors.accent),
            const SizedBox(width: 8),
            Expanded(child: Text(e.from, style: TextStyle(color: RwColors.text))),
          ]),
          if (e.description != null) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(child: Text(e.description!, style: TextStyle(color: RwColors.muted, height: 1.4))),
            ),
          ],
          if (e.url != null && Uri.tryParse(e.url!) != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse(e.url!), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(tr('Meer informatie')),
            ),
          ],
        ]),
      ),
    ),
  );
}

Future<void> openClubEvents(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ClubEventsScreen()));

/// Alle clubevenementen + gekoppelde agenda's beheren.
class ClubEventsScreen extends ConsumerStatefulWidget {
  const ClubEventsScreen({super.key});

  @override
  ConsumerState<ClubEventsScreen> createState() => _ClubEventsScreenState();
}

class _ClubEventsScreenState extends ConsumerState<ClubEventsScreen> {
  bool _busy = false;

  Future<void> _add() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Clubagenda koppelen')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            tr('Plak de agenda-link (iCal, eindigt vaak op .ics of begint met webcal://). Die vind je op de site van je club, bij "Agenda" of "Abonneren".'),
            style: TextStyle(color: RwColors.muted, fontSize: 13.5, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: tr('Agenda-link'), hintText: 'https://…/agenda.ics'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: Text(tr('Koppelen'))),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await ref.read(clubEventsServiceProvider).addLink(url);
      ref.invalidate(clubEventsProvider);
      if (mounted) showMessage(context, trf('Gekoppeld: {n} komende evenementen.', {'n': '$n'}));
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ClubCalendarLink l) async {
    await ref.read(clubEventsServiceProvider).removeLink(l.url);
    ref.invalidate(clubEventsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(clubEventsProvider);
    final state = async.value;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Clubevenementen'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'club-agenda',
        onPressed: _busy ? null : _add,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_link),
        label: Text(tr('Agenda koppelen')),
      ),
      body: state == null
          ? (async.hasError ? ErrorView(message: '${async.error}', onRetry: () => ref.invalidate(clubEventsProvider)) : LoadingView(cards: 3))
          : RefreshIndicator(
              onRefresh: () async {
                await ref.read(clubEventsServiceProvider).calendarEvents(force: true);
                ref.invalidate(clubEventsProvider);
                await ref.read(clubEventsProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  if (state.events.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: EmptyState(
                        icon: Icons.event_outlined,
                        title: tr('Nog geen evenementen'),
                        message: tr('Koppel de agenda van je loopclub of plan een groepsrun in een loopgroep.'),
                      ),
                    ),
                  for (final e in state.events)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(height: 104, child: ClubEventCard(event: e, onTap: () => openClubEvent(context, ref, e))),
                    ),
                  if (state.links.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SectionLabel(tr("Gekoppelde agenda's")),
                    const SizedBox(height: 6),
                    for (final l in state.links)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.link, color: RwColors.accent),
                        title: Text(l.name),
                        subtitle: Text(Uri.tryParse(l.url)?.host ?? l.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          tooltip: tr('Ontkoppelen'),
                          icon: const Icon(Icons.link_off),
                          onPressed: () => _remove(l),
                        ),
                      ),
                    Text(
                      tr('De agenda-link blijft op je telefoon en wordt elke 6 uur ververst.'),
                      style: TextStyle(color: RwColors.subtle, fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

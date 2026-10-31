import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/services/roster_service.dart';
import '../../domain/roster.dart';
import '../../shared/widgets.dart';

void openRosterScreen(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RosterScreen()));

/// Kaartje in de weekplanner: rooster gekoppeld of niet.
class RosterCard extends ConsumerWidget {
  const RosterCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(rosterProvider).value ?? const RosterState();
    final next = r.upcoming.isEmpty ? null : r.upcoming.first;
    return RwCard(
      title: tr('WERKROOSTER'),
      onTap: () => openRosterScreen(context),
      child: Row(children: [
        Expanded(
          child: Text(
            !r.linked
                ? tr('Werk je in diensten? Koppel je rooster, dan stelt Kadans nooit een moment voor tijdens je dienst, je reistijd of je slaap na een nachtdienst.')
                : next == null
                    ? tr('Rooster gekoppeld, maar er staan geen diensten meer in.')
                    : trf('Rooster gekoppeld. Volgende dienst: {dienst}', {'dienst': shiftLabel(next)}),
            style: const TextStyle(height: 1.45),
          ),
        ),
        Icon(r.linked ? Icons.event_busy_outlined : Icons.add_link, color: RwColors.subtle),
      ]),
    );
  }
}

/// Rooster koppelen: agenda-link (wordt bijgehouden) of een los .ics-bestand.
class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key});

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  final _url = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _url.text = ref.read(rosterProvider).value?.url ?? '';
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _run(Future<RosterState> Function() action) async {
    setState(() => _busy = true);
    try {
      final st = await action();
      ref.invalidate(rosterProvider);
      if (mounted) {
        showMessage(
          context,
          st.upcoming.isEmpty
              ? tr('Gekoppeld, maar er staan nog geen diensten in voor de komende 3 weken.')
              : trf('Gekoppeld: {n} diensten in de komende 3 weken.', {'n': st.upcoming.length}),
        );
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFile() async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(type: FileType.any);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      return;
    }
    final path = file?.path;
    if (path == null) return;
    await _run(() async => ref.read(rosterServiceProvider).linkFile(await File(path).readAsString()));
  }

  Future<void> _setOptions({int? travel, bool? rest}) async {
    await ref.read(rosterServiceProvider).setOptions(travelMinutes: travel, restAfterNight: rest);
    ref.invalidate(rosterProvider);
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(rosterProvider).value ?? const RosterState();
    final blocks = r.blocks;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Werkrooster'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr('Kadans kijkt in je rooster en slaat je diensten over, met reistijd ervoor en erna. Na een nachtdienst krijg je eerst tijd om te slapen.'),
            style: TextStyle(color: RwColors.muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          RwCard(
            title: tr('AGENDA-LINK (AANRADER)'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                tr('Veel roosterapps en Google Agenda hebben een "iCal-link" of "agenda abonneren". Plak die hier; Kadans haalt nieuwe en geruilde diensten vanzelf op.'),
                style: TextStyle(color: RwColors.muted, height: 1.4, fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'https://… of webcal://…'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy || _url.text.trim().isEmpty ? null : () => _run(() => ref.read(rosterServiceProvider).linkUrl(_url.text)),
                icon: const Icon(Icons.link),
                label: Text(tr('Koppelen')),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(tr('Of kies een .ics-bestand')),
          ),
          const SizedBox(height: 16),
          RwCard(
            title: tr('INSTELLINGEN'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Reistijd vóór en na je dienst'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final m in const [0, 15, 30, 45, 60])
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: r.options.travelMinutes == m,
                    onSelected: (_) => _setOptions(travel: m),
                  ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Eerst slapen na een nachtdienst')),
                subtitle: Text(tr('Geen loopmoment in de 6 uur na een nachtdienst.')),
                value: r.options.restAfterNight,
                onChanged: (v) => _setOptions(rest: v),
              ),
            ]),
          ),
          if (r.linked) ...[
            const SizedBox(height: 16),
            RwCard(
              title: tr('KOMENDE DIENSTEN'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (blocks.isEmpty) Text(tr('Geen diensten gevonden.'), style: TextStyle(color: RwColors.muted)),
                for (final b in blocks.take(14))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Icon(b.rest ? Icons.bedtime_outlined : Icons.work_outline, size: 18, color: b.rest ? RwColors.accentLight : RwColors.subtle),
                      const SizedBox(width: 10),
                      Expanded(child: Text(b.rest ? '${shiftLabel(b).split(' (').first} · ${tr('slapen')}' : shiftLabel(b))),
                    ]),
                  ),
                const SizedBox(height: 6),
                Text(
                  r.fromFile
                      ? tr('Uit een bestand: kies opnieuw een bestand als je rooster verandert.')
                      : tr('Wordt elke 6 uur bijgewerkt.'),
                  style: TextStyle(color: RwColors.subtle, fontSize: 12),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await ref.read(rosterServiceProvider).unlink();
                _url.clear();
                ref.invalidate(rosterProvider);
              },
              child: Text(tr('Rooster ontkoppelen'), style: TextStyle(color: RwColors.danger)),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            tr('Je rooster blijft op je telefoon; het gaat niet naar Kadans-servers.'),
            style: TextStyle(color: RwColors.subtle, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

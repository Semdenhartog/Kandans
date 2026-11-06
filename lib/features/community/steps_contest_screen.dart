import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/health_consent.dart';
import '../../data/services/social_service.dart';
import '../../data/services/sync_service.dart';
import '../../data/services/together_service.dart';
import '../../shared/widgets.dart';
import 'runner_avatar.dart';
import 'runner_profile_screen.dart';
import '../profile/share_app_screen.dart' show openShareApp;

void openStepsContest(BuildContext c) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const StepsContestScreen()));

const _months = ['januari', 'februari', 'maart', 'april', 'mei', 'juni', 'juli', 'augustus', 'september', 'oktober', 'november', 'december'];

String formatSteps(int n) {
  final t = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < t.length; i++) {
    if (i > 0 && (t.length - i) % 3 == 0) b.write('.');
    b.write(t[i]);
  }
  return b.toString();
}

/// Stappenwedstrijd van de maand: wie zet de meeste stappen, met vrienden of per loopgroep.
/// Stappen komen uit Health Connect (telefoon of horloge); alleen het maandtotaal gaat naar de server.
class StepsContestScreen extends ConsumerStatefulWidget {
  const StepsContestScreen({super.key, this.preview});

  /// Voor schermafbeeldingen: vaste ranglijst zonder Health Connect of server.
  final List<StepEntry>? preview;

  @override
  ConsumerState<StepsContestScreen> createState() => _StepsContestScreenState();
}

class _StepsContestScreenState extends ConsumerState<StepsContestScreen> {
  bool _loading = true;
  bool _connected = false;
  bool _connecting = false;
  int? _mySteps;
  int? _today;
  String? _error;
  List<RunGroup> _groups = const [];

  /// null = vrienden; anders het id van een loopgroep.
  int? _group;
  bool _lastMonth = false;
  List<StepEntry> _board = const [];

  SocialService get _social => ref.read(socialServiceProvider);
  SyncService get _sync => ref.read(syncServiceProvider);

  DateTime get _month {
    final n = DateTime.now();
    return _lastMonth ? DateTime(n.year, n.month - 1) : DateTime(n.year, n.month);
  }

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      _connected = true;
      _loading = false;
      _board = widget.preview!;
      _mySteps = widget.preview!.where((e) => e.isMe).firstOrNull?.steps;
    } else {
      _start();
    }
  }

  Future<void> _start() async {
    _connected = Platform.isAndroid && await _sync.stepsEnabled();
    try {
      _groups = await ref.read(togetherServiceProvider).groups();
    } catch (_) {}
    await _refresh();
  }

  /// Eigen stappen doorgeven (deze maand, en in de eerste dagen ook nog het eindtotaal van vorige maand)
  /// en de ranglijst ophalen.
  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_connected) {
        final now = DateTime.now();
        final steps = await _sync.monthSteps(now);
        _today = await _sync.todaySteps();
        if (steps != null) {
          _mySteps = steps;
          await _social.submitSteps(now, steps);
        }
        if (now.day <= 3) {
          final prev = DateTime(now.year, now.month - 1);
          final p = await _sync.monthSteps(prev);
          if (p != null) await _social.submitSteps(prev, p).catchError((Object _) {});
        }
      }
      final board = await _social.stepsBoard(_group == null ? 'friends' : 'group', groupId: _group, month: _month);
      if (!mounted) return;
      setState(() {
        _board = board;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      if (!await HealthConsent.ensure(context)) return;
      final ok = await _sync.connectSteps();
      if (!mounted) return;
      if (!ok) {
        showMessage(context, tr('Geen toestemming voor stappen. Je kunt het later opnieuw proberen.'), error: true);
        return;
      }
      setState(() => _connected = true);
      await _refresh();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = daysInMonth - now.day;
    final me = _board.where((e) => e.isMe).firstOrNull;
    final shownSteps = _lastMonth ? me?.steps : (_mySteps ?? me?.steps);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Stappen van de maand'))),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // Kop: jouw stand deze maand.
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: RwColors.surface,
                borderRadius: BorderRadius.circular(RwRadius.l),
                border: Border.all(color: RwColors.bar),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${tr(_months[_month.month - 1])} ${_month.year}'.toUpperCase(),
                    style: RwText.label.copyWith(letterSpacing: 1.2)),
                const SizedBox(height: 6),
                Text(shownSteps == null ? '–' : formatSteps(shownSteps),
                    style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 44, fontWeight: FontWeight.w800, color: RwColors.accent)),
                Text(tr('stappen'), style: TextStyle(color: RwColors.muted)),
                const SizedBox(height: 10),
                Wrap(spacing: 16, runSpacing: 6, children: [
                  if (me != null) _Pill(Icons.emoji_events_outlined, trf('Plek {n} van {totaal}', {'n': me.rank, 'totaal': _board.length})),
                  if (!_lastMonth) _Pill(Icons.hourglass_bottom, daysLeft == 0 ? tr('Laatste dag!') : trf('Nog {n} dagen', {'n': daysLeft})),
                  if (!_lastMonth && _today != null) _Pill(Icons.today_outlined, trf('Vandaag {n}', {'n': formatSteps(_today!)})),
                  if (!_lastMonth && me != null && me.rank > 1)
                    _Pill(Icons.trending_up, trf('Nog {n} om iemand in te halen', {
                      // Wie het dichtst vóór je staat: het laagste aantal stappen boven jou.
                      'n': formatSteps(_board.where((e) => e.rank < me.rank).map((e) => e.steps).reduce((a, b) => a < b ? a : b) - me.steps + 1),
                    })),
                  if (!_lastMonth && shownSteps != null && now.day > 0)
                    _Pill(Icons.show_chart, trf('{n} per dag', {'n': formatSteps((shownSteps / now.day).round())})),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            if (!_connected)
              RwCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(tr('Doe mee met je stappen'), style: RwText.title),
                  const SizedBox(height: 6),
                  Text(
                    tr('Kadans leest je stappen uit Health Connect (van je telefoon of horloge, ook Garmin via Health Connect). '
                        'Alleen je totaal van de maand gaat naar de ranglijst; geen dagen, tijden of plekken.'),
                    style: TextStyle(color: RwColors.muted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _connecting || !Platform.isAndroid ? null : _connect,
                    icon: const Icon(Icons.directions_walk),
                    label: Text(Platform.isAndroid ? tr('Stappen koppelen') : tr('Alleen op Android')),
                  ),
                ]),
              ),
            const SizedBox(height: 4),
            // Tegen wie: vrienden of een loopgroep. En deze of vorige maand.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ChoiceChip(
                  label: Text(tr('Vrienden')),
                  selected: _group == null,
                  onSelected: (_) {
                    setState(() => _group = null);
                    _refresh();
                  },
                ),
                for (final g in _groups) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(g.name),
                    selected: _group == g.id,
                    onSelected: (_) {
                      setState(() => _group = g.id);
                      _refresh();
                    },
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _lastMonth = !_lastMonth);
                  _refresh();
                },
                icon: Icon(_lastMonth ? Icons.arrow_forward : Icons.history, size: 18),
                label: Text(_lastMonth ? tr('Naar deze maand') : tr('Uitslag vorige maand')),
              ),
            ),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              ErrorView(message: _error!, onRetry: _refresh)
            else if (_board.length <= 1)
              EmptyState(
                icon: Icons.groups_outlined,
                title: tr('Nog geen tegenstanders'),
                message: _group == null
                    ? tr('Volg andere lopers in Samen, of nodig vrienden uit. Iedereen die zijn stappen koppelt, staat hier.')
                    : tr('Nog niemand anders in deze groep heeft stappen gekoppeld. Vraag het in de groep!'),
                actionLabel: tr('Vrienden uitnodigen'),
                onAction: () => openShareApp(context, name: ''),
              )
            else
              for (final e in _board) _Row(entry: e, leader: _board.first.steps),
            const SizedBox(height: 12),
            Text(
              tr('De wedstrijd begint elke 1e van de maand opnieuw. Health Connect telt telefoon en horloge samen maar één keer.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: RwColors.accent),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ]);
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.leader});
  final StepEntry entry;
  final int leader;

  static const _medals = [Color(0xFFD9A441), Color(0xFFB8BEC6), Color(0xFFC0814A)];

  @override
  Widget build(BuildContext context) {
    final medal = entry.rank >= 1 && entry.rank <= 3 ? _medals[entry.rank - 1] : null;
    final share = leader <= 0 ? 0.0 : (entry.steps / leader).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: entry.isMe ? RwColors.accent.withValues(alpha: 0.12) : RwColors.surface,
        borderRadius: BorderRadius.circular(RwRadius.m),
        child: InkWell(
          borderRadius: BorderRadius.circular(RwRadius.m),
          onTap: entry.isMe ? null : () => openRunnerProfile(context, entry.nickname),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            child: Row(children: [
              SizedBox(
                width: 30,
                child: medal != null
                    ? Icon(Icons.emoji_events, color: medal, size: 24)
                    : Text('${entry.rank}', textAlign: TextAlign.center, style: RwText.number.copyWith(fontSize: 16)),
              ),
              const SizedBox(width: 8),
              RunnerAvatar(entry.nickname, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entry.isMe ? trf('{naam} (jij)', {'naam': entry.nickname}) : entry.nickname,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(RwRadius.s),
                    child: LinearProgressIndicator(value: share, minHeight: 6, backgroundColor: RwColors.bar, color: RwColors.accent),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              Text(formatSteps(entry.steps), style: RwText.number.copyWith(fontSize: 16)),
            ]),
          ),
        ),
      ),
    );
  }
}

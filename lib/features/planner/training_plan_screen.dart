import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/training_load.dart';
import '../../domain/training_plan.dart';
import '../../domain/weekly_load.dart';
import '../../shared/widgets.dart';
import '../record/record_run_screen.dart';

void openTrainingPlan(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TrainingPlanScreen()));
}

const _dayNames = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];

IconData sessionIcon(SessionKind k) => switch (k) {
      SessionKind.easy => Icons.directions_walk,
      SessionKind.long => Icons.route_outlined,
      SessionKind.tempo => Icons.speed,
      SessionKind.interval => Icons.timer_outlined,
      SessionKind.race => Icons.emoji_events_outlined,
    };

Color sessionColor(SessionKind k) => switch (k) {
      SessionKind.easy => RwColors.good,
      SessionKind.long => const Color(0xFF5AA9FF),
      SessionKind.tempo => RwColors.warning,
      SessionKind.interval => RwColors.accent,
      SessionKind.race => RwColors.danger,
    };

/// Start een training uit het schema met de juiste instellingen.
void startSession(BuildContext context, PlanSession s) {
  openRecorder(context, plan: s.intervals, targetPace: s.intervals == null ? s.targetPace : null, sessionTitle: s.title);
}

/// Trainingsschema naar je wedstrijd of afstand (zoals Runna), gratis.
class TrainingPlanScreen extends ConsumerStatefulWidget {
  const TrainingPlanScreen({super.key});

  @override
  ConsumerState<TrainingPlanScreen> createState() => _TrainingPlanScreenState();
}

class _TrainingPlanScreenState extends ConsumerState<TrainingPlanScreen> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(planProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trainingsschema'),
        actions: [
          if (!_editing && (plan.value?.isNotEmpty ?? false))
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'new') setState(() => _editing = true);
                if (v == 'delete') {
                  final ok = await confirmDialog(context, title: 'Schema verwijderen?', message: 'Je trainingsschema wordt verwijderd. Je runs blijven staan.');
                  if (!ok) return;
                  await ref.read(repositoryProvider).savePlan(const []);
                  ref.invalidate(planProvider);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'new', child: Text('Nieuw schema maken')),
                PopupMenuItem(value: 'delete', child: Text('Schema verwijderen')),
              ],
            ),
        ],
      ),
      body: plan.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(planProvider)),
        data: (sessions) => _editing || sessions.isEmpty
            ? _PlanSetupView(onDone: () => setState(() => _editing = false), canCancel: sessions.isNotEmpty)
            : _PlanView(sessions: sessions),
      ),
    );
  }
}

class _PlanView extends ConsumerWidget {
  const _PlanView({required this.sessions});
  final List<PlanSession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final done = [for (final a in runs) (start: a.startedAt, meters: a.distanceMeters, seconds: a.movingTimeSeconds)];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final race = sessions.last;
    final past = sessions.where((s) => s.date.isBefore(today)).toList();
    final donePast = past.where((s) => sessionDone(s, done)).length;
    final weeks = <int, List<PlanSession>>{};
    for (final s in sessions) {
      weeks.putIfAbsent(s.week, () => []).add(s);
    }
    final daysLeft = race.date.difference(today).inDays;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        RwCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(race.title, style: const TextStyle(fontFamily: RwFonts.display, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                daysLeft > 0 ? 'Nog $daysLeft dagen · ${Fmt.dateLong(race.date)}' : (daysLeft == 0 ? 'Vandaag is het zover!' : 'Je schema is afgelopen.'),
                style: const TextStyle(color: RwColors.muted),
              ),
              if (past.isNotEmpty) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: donePast / past.length, minHeight: 8, color: RwColors.accent, backgroundColor: RwColors.bar),
                ),
                const SizedBox(height: 4),
                Text('$donePast van ${past.length} trainingen tot nu toe gedaan', style: const TextStyle(color: RwColors.subtle, fontSize: 12)),
              ],
            ],
          ),
        ),
        for (final e in weeks.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
            child: Text(
              'WEEK ${e.key}${e.value.any((s) => weekStart(s.date) == weekStart(today)) ? ' · DEZE WEEK' : ''}',
              style: const TextStyle(fontSize: 13, color: RwColors.subtle, fontWeight: FontWeight.w600, letterSpacing: 0.4),
            ),
          ),
          for (final s in e.value) _SessionTile(session: s, done: sessionDone(s, done), today: today),
        ],
        const SizedBox(height: 12),
        const Text(
          'Het schema bouwt geleidelijk op, met elke 4e week wat rustiger en de laatste 2 weken afbouwen. '
          'Mis je een training? Geen probleem, ga gewoon verder met de volgende.',
          style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.done, required this.today});
  final PlanSession session;
  final bool done;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final isToday = s.date == today;
    final missed = s.date.isBefore(today) && !done;
    final color = sessionColor(s.kind);
    return Card(
      shape: isToday
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: RwColors.accent, width: 1.5))
          : null,
      child: ExpansionTile(
        shape: const Border(),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.18),
          child: done ? const Icon(Icons.check, color: RwColors.good) : Icon(sessionIcon(s.kind), color: color),
        ),
        title: Text(s.title, style: TextStyle(fontWeight: FontWeight.w600, color: missed ? RwColors.subtle : RwColors.text)),
        subtitle: Text(
          '${isToday ? 'Vandaag' : '${_dayNames[s.date.weekday - 1]} ${s.date.day}-${s.date.month}'}'
          '${done ? ' · gedaan' : (missed ? ' · overgeslagen' : '')}',
          style: TextStyle(color: isToday ? RwColors.accent : RwColors.subtle),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.description, style: const TextStyle(color: RwColors.muted, height: 1.4)),
          if (!s.date.isBefore(today) && s.kind != SessionKind.race) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => startSession(context, s),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start deze training'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanSetupView extends ConsumerStatefulWidget {
  const _PlanSetupView({required this.onDone, required this.canCancel});
  final VoidCallback onDone;
  final bool canCancel;

  @override
  ConsumerState<_PlanSetupView> createState() => _PlanSetupViewState();
}

class _PlanSetupViewState extends ConsumerState<_PlanSetupView> {
  static const _goals = {5000.0: '5 km', 10000.0: '10 km', 21097.5: 'Halve marathon', 42195.0: 'Marathon'};
  double _goal = 10000;
  late DateTime _date = DateTime.now().add(const Duration(days: 70));
  final _goalTime = TextEditingController();
  final Set<int> _days = {2, 4, 7};
  int _longDay = 7;
  List<PlanSession>? _preview;
  bool _saving = false;

  @override
  void dispose() {
    _goalTime.dispose();
    super.dispose();
  }

  void _useRace(RaceEvent r) {
    setState(() {
      final match = _goals.keys.where((g) => (g - r.distanceMeters).abs() < 600).firstOrNull;
      _goal = match ?? (r.distanceMeters <= 7500 ? 5000 : r.distanceMeters <= 15000 ? 10000 : r.distanceMeters <= 30000 ? 21097.5 : 42195);
      _date = r.raceDate;
      _goalTime.text = Fmt.duration(r.goalTimeSeconds);
      _preview = null;
    });
  }

  void _make() {
    final runs = ref.read(activitiesProvider).value ?? const <Activity>[];
    final weeks = weeklyTotals(runs, DateTime.now(), weeks: 4);
    final weekly = weeks.fold<double>(0, (s, w) => s + w.km) / 4;
    final goalSeconds = Fmt.parseDuration(_goalTime.text);
    final plan = buildPlan(
      PlanSetup(
        goalMeters: _goal,
        raceDate: _date,
        runDays: _days.toList(),
        longRunDay: _days.contains(_longDay) ? _longDay : (_days.toList()..sort()).last,
        currentWeeklyKm: weekly,
        thresholdPace: estimateThresholdPace(runs),
        goalTimeSeconds: goalSeconds,
      ),
      DateTime.now(),
    );
    if (plan.isEmpty) {
      showMessage(context, 'Kies een datum die minstens een week weg is, en minstens één loopdag.');
      return;
    }
    setState(() => _preview = plan);
  }

  Future<void> _save() async {
    final p = _preview;
    if (p == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).savePlan(p);
      ref.invalidate(planProvider);
      widget.onDone();
      if (mounted) showMessage(context, 'Je schema staat klaar. Je ziet de training van vandaag ook op Vandaag.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 13, color: RwColors.subtle, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
      );

  @override
  Widget build(BuildContext context) {
    final races = (ref.watch(racesProvider).value ?? const <RaceEvent>[]).where((r) => r.daysUntil >= 7).toList();
    final preview = _preview;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        const Text(
          'Een schema op maat: rustige duurlopen, intervallen, tempolopen en een lange duurloop, '
          'geleidelijk opgebouwd naar je doel. De stem in de app begeleidt je bij elke training.',
          style: TextStyle(color: RwColors.muted, height: 1.4),
        ),
        if (races.isNotEmpty) ...[
          _label('WEDSTRIJD'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in races) ActionChip(avatar: const Icon(Icons.emoji_events_outlined, size: 18), label: Text(r.name), onPressed: () => _useRace(r)),
          ]),
        ],
        _label('DOEL'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in _goals.entries)
            ChoiceChip(label: Text(e.value), selected: _goal == e.key, onSelected: (_) => setState(() {
                  _goal = e.key;
                  _preview = null;
                })),
        ]),
        _label('DATUM'),
        OutlinedButton.icon(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime.now().add(const Duration(days: 7)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (d != null) {
              setState(() {
                _date = d;
                _preview = null;
              });
            }
          },
          icon: const Icon(Icons.event),
          label: Text('${Fmt.dateLong(_date)} · over ${(_date.difference(DateTime.now()).inDays / 7).ceil()} weken'),
        ),
        _label('DOELTIJD (OPTIONEEL)'),
        TextField(
          controller: _goalTime,
          decoration: const InputDecoration(hintText: 'bijv. 50:00 of 1:55:00', isDense: true),
          keyboardType: TextInputType.datetime,
          onChanged: (_) => _preview = null,
        ),
        _label('LOOPDAGEN'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var d = 1; d <= 7; d++)
            FilterChip(
              label: Text(_dayNames[d - 1]),
              selected: _days.contains(d),
              onSelected: (on) => setState(() {
                on ? _days.add(d) : _days.remove(d);
                _preview = null;
              }),
            ),
        ]),
        _label('LANGE DUURLOOP OP'),
        Wrap(spacing: 6, children: [
          for (final d in (_days.toList()..sort()))
            ChoiceChip(label: Text(_dayNames[d - 1]), selected: _longDay == d, onSelected: (_) => setState(() {
                  _longDay = d;
                  _preview = null;
                })),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          if (widget.canCancel) ...[
            Expanded(child: OutlinedButton(onPressed: widget.onDone, child: const Text('Annuleren'))),
            const SizedBox(width: 12),
          ],
          Expanded(child: FilledButton(onPressed: _days.isEmpty ? null : _make, child: Text(preview == null ? 'Maak mijn schema' : 'Opnieuw maken'))),
        ]),
        if (preview != null) ...[
          const SizedBox(height: 20),
          RwCard(
            title: 'VOORBEELD',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${preview.last.week} weken · ${preview.length} trainingen', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final s in preview.take(6))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Icon(sessionIcon(s.kind), size: 18, color: sessionColor(s.kind)),
                      const SizedBox(width: 8),
                      SizedBox(width: 64, child: Text('${_dayNames[s.date.weekday - 1]} ${s.date.day}-${s.date.month}', style: const TextStyle(color: RwColors.subtle))),
                      Expanded(child: Text(s.title)),
                    ]),
                  ),
                const Text('…', style: TextStyle(color: RwColors.subtle)),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Schema opslaan'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

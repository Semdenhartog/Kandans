import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/beginner_plan.dart';
import '../../domain/clothing.dart';
import '../../domain/start_time_scoring.dart';
import '../dashboard/dashboard_providers.dart';
import '../../domain/plan_check.dart';
import '../../domain/readiness.dart';
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
/// Met [weather] wordt het doeltempo aangepast als het warm is (zoals Runna's "Adapt for Heat").
void startSession(BuildContext context, PlanSession s, {HourWeather? weather}) {
  var pace = s.intervals == null ? s.targetPace : null;
  final feels = weather?.feelsLike ?? weather?.temperature;
  if (pace != null && feels != null) {
    final adjusted = heatAdjustedPace(pace, feelsLike: feels, humidity: weather?.humidity);
    if (adjusted - pace >= 3) {
      showMessage(context,
          'Het is ${Fmt.temp(feels)} (gevoel). Je doeltempo is aangepast naar ${Fmt.pace(adjusted)} in plaats van ${Fmt.pace(pace)}.');
      pace = adjusted;
    }
  }
  openRecorder(context, plan: s.intervals, targetPace: pace, sessionTitle: s.title);
}

const _setupKey = 'plan_setup';

Future<void> _rememberSetup(PlanSetup setup) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_setupKey, jsonEncode(setup.toJson()));
  } catch (_) {}
}

Future<void> _forgetSetup() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.remove(_setupKey);
  } catch (_) {}
}

Future<PlanSetup?> _savedSetup() async {
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_setupKey);
    return raw == null ? null : PlanSetup.fromJson(jsonDecode(raw));
  } catch (_) {
    return null;
  }
}

/// Tempo's in je schema bijwerken op basis van je recente runs (zoals Runna's pace-recalibratie).
Future<void> recalibrateTrainingPlan(BuildContext context, WidgetRef ref) async {
  final setup = await _savedSetup();
  if (!context.mounted) return;
  if (setup == null) {
    showMessage(context, 'Tempo\'s bijwerken werkt bij schema\'s naar een afstand. Een beginnersschema werkt op tijd, niet op tempo.');
    return;
  }
  final runs = ref.read(activitiesProvider).value ?? const <Activity>[];
  final plan = ref.read(planProvider).value ?? const <PlanSession>[];
  final now = DateTime.now();
  final fresh = recalibratedThreshold(runs, now, fallback: estimateThresholdPace(runs));
  final weeks = weeklyTotals(runs, now, weeks: 4);
  final weekly = weeks.fold<double>(0, (s, w) => s + w.km) / 4;
  final diff = fresh - setup.thresholdPace;
  final ok = await confirmDialog(
    context,
    title: 'Tempo\'s bijwerken?',
    message: diff.abs() < 2
        ? 'Je drempeltempo is gelijk gebleven (${Fmt.pace(fresh)}). De komende trainingen worden opnieuw ingedeeld met je huidige weekomvang.'
        : 'Je drempeltempo is ${diff < 0 ? 'sneller' : 'langzamer'} geworden: ${Fmt.pace(fresh)} (was ${Fmt.pace(setup.thresholdPace)}). '
            'De trainingen vanaf vandaag krijgen nieuwe tempo\'s. Wat je al deed blijft staan.',
    confirmLabel: 'Bijwerken',
    destructive: false,
  );
  if (!ok || !context.mounted) return;
  final next = setup.copyWith(thresholdPace: fresh, currentWeeklyKm: weekly);
  try {
    await ref.read(repositoryProvider).savePlan(recalibratePlan(plan, next, now));
    await _rememberSetup(next);
    ref.invalidate(planProvider);
    if (context.mounted) showMessage(context, 'Je schema is bijgewerkt.');
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
  }
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
                if (v == 'recal') await recalibrateTrainingPlan(context, ref);
                if (v == 'delete') {
                  final ok = await confirmDialog(context, title: 'Schema verwijderen?', message: 'Je trainingsschema wordt verwijderd. Je runs blijven staan.');
                  if (!ok) return;
                  await ref.read(repositoryProvider).savePlan(const []);
                  ref.invalidate(planProvider);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'recal', child: Text('Tempo\'s bijwerken')),
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
    // De schemaweek waar vandaag in valt (of de eerstvolgende).
    final currentWeek = sessions.where((s) => !s.date.isBefore(today)).firstOrNull?.week;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        if (daysLeft < 0) _PlanReplay(sessions: sessions, runs: runs),
        const PlanCheckCard(),
        RwCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(race.title, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 22, fontWeight: FontWeight.w800)),
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
        for (final e in weeks.entries)
          if (e.value.every((s) => s.date.isBefore(today)))
            // Voorbije weken ingeklapt, zodat je meteen bij deze week bent.
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Card(
                child: ExpansionTile(
                  shape: const Border(),
                  // Weeknummer in een ring die laat zien hoeveel je van die week deed (vol = alles).
                  leading: Builder(builder: (context) {
                    final n = e.value.where((s) => sessionDone(s, done)).length;
                    final f = e.value.isEmpty ? 0.0 : n / e.value.length;
                    final c = f >= 1 ? RwColors.good : (f >= 0.6 ? RwColors.accent : RwColors.warning);
                    return SizedBox(
                      width: 40,
                      height: 40,
                      child: Stack(alignment: Alignment.center, children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: f),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, _) => SizedBox.expand(
                            child: CircularProgressIndicator(value: v, strokeWidth: 3.5, strokeCap: StrokeCap.round, color: c, backgroundColor: RwColors.bar),
                          ),
                        ),
                        f >= 1
                            ? Icon(Icons.check_rounded, size: 20, color: c)
                            : Text('${e.key}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      ]),
                    );
                  }),
                  title: Text('Week ${e.key}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${e.value.where((s) => sessionDone(s, done)).length} van ${e.value.length} gedaan',
                    style: const TextStyle(color: RwColors.subtle),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  children: [for (final s in e.value) _SessionTile(session: s, done: sessionDone(s, done), today: today)],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
              child: Text(
                'WEEK ${e.key}${e.key == currentWeek ? ' · NU' : ''}',
                style: TextStyle(
                  fontSize: 13,
                  color: e.key == currentWeek ? RwColors.accent : RwColors.subtle,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
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
              onPressed: () => showSessionBriefing(context, s),
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
  static final _goals = <double, String>{5000.0: '5 km', 10000.0: '10 km', 21097.5: 'Halve marathon', 42195.0: 'Marathon'};
  double _goal = 10000;
  late DateTime _date = DateTime.now().add(const Duration(days: 70));
  final _goalTime = TextEditingController();
  final Set<int> _days = {2, 4, 7};
  int _longDay = 7;
  List<PlanSession>? _preview;
  PlanSetup? _setup;

  /// null = naar een afstand; anders een beginnersschema.
  BeginnerProgram? _program;
  int _weeks = BeginnerProgram.start.defaultWeeks;
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
    final program = _program;
    if (program != null) {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final plan = buildBeginnerPlan(program, start: tomorrow, runDays: _days.toList(), weeks: _weeks);
      setState(() {
        _preview = plan;
        _setup = null;
      });
      return;
    }
    final runs = ref.read(activitiesProvider).value ?? const <Activity>[];
    final weeks = weeklyTotals(runs, DateTime.now(), weeks: 4);
    final weekly = weeks.fold<double>(0, (s, w) => s + w.km) / 4;
    final goalSeconds = Fmt.parseDuration(_goalTime.text);
    final setup = PlanSetup(
      goalMeters: _goal,
      raceDate: _date,
      runDays: _days.toList(),
      longRunDay: _days.contains(_longDay) ? _longDay : (_days.toList()..sort()).last,
      currentWeeklyKm: weekly,
      thresholdPace: estimateThresholdPace(runs),
      goalTimeSeconds: goalSeconds,
    );
    final plan = buildPlan(setup, DateTime.now());
    if (plan.isEmpty) {
      showMessage(context, 'Kies een datum die minstens een week weg is, en minstens één loopdag.');
      return;
    }
    setState(() {
      _preview = plan;
      _setup = setup;
    });
  }

  Future<void> _save() async {
    final p = _preview;
    if (p == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).savePlan(p);
      if (_setup != null) {
        await _rememberSetup(_setup!);
      } else {
        await _forgetSetup();
      }
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
        child: Text(t, style: RwText.overline),
      );

  @override
  Widget build(BuildContext context) {
    final races = (ref.watch(racesProvider).value ?? const <RaceEvent>[]).where((r) => r.daysUntil >= 7).toList();
    final preview = _preview;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _label('WAT WIL JE?'),
        for (final (p, title, text, icon) in [
          (null, 'Naar een afstand', '5 km, 10 km, halve of hele marathon, met tempo\'s en intervallen.', Icons.flag_outlined),
          (BeginnerProgram.start, BeginnerProgram.start.title, BeginnerProgram.start.description, Icons.directions_walk),
          (BeginnerProgram.comeback, BeginnerProgram.comeback.title, BeginnerProgram.comeback.description, Icons.healing_outlined),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: _program == p ? RwColors.accent : RwColors.border, width: _program == p ? 1.5 : 1),
              ),
              child: ListTile(
                leading: Icon(icon, color: _program == p ? RwColors.accent : RwColors.muted),
                title: Text(title),
                subtitle: Text(text),
                onTap: () => setState(() {
                  _program = p;
                  if (p != null) {
                    _weeks = p.defaultWeeks;
                    if (_days.length > 4) {
                      _days
                        ..clear()
                        ..addAll({2, 4, 7});
                    }
                  }
                  _preview = null;
                }),
              ),
            ),
          ),
        if (_program != null) ...[
          _label('AANTAL WEKEN'),
          Row(children: [
            Expanded(
              child: Slider(
                value: _weeks.toDouble(),
                min: _program!.minWeeks.toDouble(),
                max: _program!.maxWeeks.toDouble(),
                divisions: _program!.maxWeeks - _program!.minWeeks,
                label: '$_weeks weken',
                onChanged: (v) => setState(() {
                  _weeks = v.round();
                  _preview = null;
                }),
              ),
            ),
            SizedBox(width: 72, child: Text('$_weeks weken', style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const Text('Meer weken = rustiger opbouwen. Twijfel je? Kies wat langer.', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
        ],
        if (_program == null && races.isNotEmpty) ...[
          _label('WEDSTRIJD'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in races) ActionChip(avatar: const Icon(Icons.emoji_events_outlined, size: 18), label: Text(r.name), onPressed: () => _useRace(r)),
          ]),
        ],
        if (_program == null) ...[
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
        ],
        _label(_program == null ? 'LOOPDAGEN' : 'LOOPDAGEN (3 IS GENOEG)'),
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
        if (_program == null) ...[
          _label('LANGE DUURLOOP OP'),
          Wrap(spacing: 6, children: [
            for (final d in (_days.toList()..sort()))
              ChoiceChip(label: Text(_dayNames[d - 1]), selected: _longDay == d, onSelected: (_) => setState(() {
                    _longDay = d;
                    _preview = null;
                  })),
          ]),
        ],
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

/// Kaart met hoe je schema loopt, met een knop om bij te sturen (gemist of te veel).
class PlanCheckCard extends ConsumerWidget {
  const PlanCheckCard({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider).value ?? const <PlanSession>[];
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final check = checkPlan(
      plan,
      [for (final a in runs) (start: a.startedAt, meters: a.distanceMeters, seconds: a.movingTimeSeconds)],
      DateTime.now(),
      fixedEnd: plan.isNotEmpty && plan.last.kind == SessionKind.race,
    );
    if (check == null || (compact && check.fix == null)) return const SizedBox.shrink();
    final color = check.warning ? RwColors.warning : (check.fix == null ? RwColors.good : RwColors.accent);
    Future<void> apply() async {
      final now = DateTime.now();
      final next = switch (check.fix!) {
        PlanFix.repeatWeek => repeatLastWeek(plan, now),
        PlanFix.lighterWeek => lighterThisWeek(plan, now),
      };
      try {
        await ref.read(repositoryProvider).savePlan(next);
        ref.invalidate(planProvider);
        if (context.mounted) showMessage(context, 'Je schema is aangepast.');
      } catch (e) {
        if (context.mounted) showMessage(context, friendlyError(e), error: true);
      }
    }

    return Padding(
      padding: EdgeInsets.only(top: compact ? 12 : 0, bottom: compact ? 0 : 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(check.warning ? Icons.trending_up : (check.fix == null ? Icons.check_circle_outline : Icons.event_repeat), color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(check.title, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 16))),
            ]),
            const SizedBox(height: 6),
            Text(check.text, style: const TextStyle(color: RwColors.muted, height: 1.4)),
            if (check.fix != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: apply,
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: Text(check.fix == PlanFix.repeatWeek ? 'Vorige week herhalen' : 'Deze week lichter maken'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

TrainingType _typeFor(PlanSession s) => switch (s.kind) {
      SessionKind.long => TrainingType.long,
      SessionKind.tempo || SessionKind.interval => TrainingType.quality,
      _ => TrainingType.easy,
    };

int _minutesOf(PlanSession s) {
  final ip = s.intervals;
  if (ip != null && ip.steps.every((x) => x.seconds != null)) {
    return (ip.steps.fold<int>(0, (a, x) => a + x.seconds!) / 60).round();
  }
  if (s.distanceMeters != null && s.targetPace != null) return (s.distanceMeters! / 1000 * s.targetPace! / 60).round();
  return 45;
}

/// Briefing vóór je training (zoals Runna's pre-workout briefing), met het weer van nú erbij:
/// wat je gaat doen, je tempo, wat je aantrekt en een tip. Daarna start je meteen.
Future<void> showSessionBriefing(BuildContext context, PlanSession session, {int? readinessScore}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final w = ref.watch(forecastProvider).value?.at(DateTime.now());
      final s = session;
      final minutes = _minutesOf(s);
      final feels = w?.feelsLike ?? w?.temperature;
      final pace = s.intervals == null || s.intervals!.walkRun ? s.targetPace : null;
      final hot = pace != null && feels != null ? heatAdjustedPace(pace, feelsLike: feels, humidity: w?.humidity) : null;
      final clothes = w == null ? null : clothingFor(w, _typeFor(s), durationMinutes: minutes);
      final walkRun = s.intervals?.walkRun ?? false;
      final tip = walkRun
          ? 'Wandelen hoort erbij en is geen falen. Loop zo rustig dat je kunt praten; de stem zegt wanneer je wisselt.'
          : switch (s.kind) {
              SessionKind.easy => 'Rustig betekent echt rustig: praten moet kunnen. Hier groeit je conditie.',
              SessionKind.long => minutes >= 60
                  ? 'Begin langzamer dan je denkt en neem drinken mee. Zet eventueel de drink- en gelherinnering aan.'
                  : 'Begin langzamer dan je denkt; aan het eind mag het iets sneller.',
              SessionKind.tempo => '"Comfortabel zwaar": je kunt nog een paar woorden zeggen, geen zinnen. Goed inlopen voorkomt blessures.',
              SessionKind.interval => 'Loop de eerste herhaling niet te hard: de laatste moet net zo snel kunnen.',
              SessionKind.race => 'Start rustig, je wint de race in de tweede helft.',
            };
      Widget row(IconData icon, String text) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 20, color: RwColors.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
            ]),
          );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                CircleAvatar(
                  backgroundColor: sessionColor(s.kind).withValues(alpha: 0.18),
                  child: Icon(sessionIcon(s.kind), color: sessionColor(s.kind)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('JOUW TRAINING', style: TextStyle(color: RwColors.subtle, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                    Text(s.title, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Text(s.description, style: const TextStyle(color: RwColors.muted, height: 1.45)),
              const Divider(height: 28),
              row(Icons.timer_outlined, 'Ongeveer $minutes minuten${s.distanceMeters != null ? ' · ${Fmt.km(s.distanceMeters!, decimals: 1)}' : ''}'),
              if (pace != null)
                row(
                  Icons.speed,
                  hot != null && hot - pace >= 3
                      ? 'Tempo rond ${Fmt.pace(hot)} (aangepast voor ${Fmt.temp(feels)}; normaal ${Fmt.pace(pace)})'
                      : 'Tempo rond ${Fmt.pace(pace)}',
                ),
              if (w != null)
                row(Icons.wb_sunny_outlined,
                    'Nu ${Fmt.temp(feels)} gevoel, wind ${Fmt.wind(w.windSpeed)}${w.windDirection == null ? '' : ' uit het ${Fmt.compass(w.windDirection!)}'}, regenkans ${Fmt.pct(w.precipitationProbability)}'),
              if (clothes != null) row(Icons.checkroom_outlined, 'Aantrekken: ${clothes.summary.toLowerCase()}'),
              if (readinessScore != null)
                row(Icons.battery_charging_full,
                    'Klaar-score $readinessScore${readinessScore < 50 ? ': overweeg de lichtere versie' : ''}'),
              row(Icons.lightbulb_outline, tip),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  startSession(context, s, weather: w);
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
              if (s.kind != SessionKind.race)
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    startSession(context, easierSession(s), weather: w);
                  },
                  child: const Text('Ik voel me niet 100%: lichter maken'),
                ),
            ],
          ),
        ),
      );
    }),
  );
}

/// Terugblik als je schema klaar is (zoals Runna's Plan Replay).
class _PlanReplay extends StatelessWidget {
  const _PlanReplay({required this.sessions, required this.runs});
  final List<PlanSession> sessions;
  final List<Activity> runs;

  @override
  Widget build(BuildContext context) {
    final from = sessions.first.date, to = sessions.last.date.add(const Duration(days: 1));
    final inPlan = runs.where((a) {
      final t = a.startedAt.toLocal();
      return !t.isBefore(from) && t.isBefore(to);
    }).toList();
    final done = [for (final a in runs) (start: a.startedAt, meters: a.distanceMeters, seconds: a.movingTimeSeconds)];
    final doneCount = sessions.where((s) => sessionDone(s, done)).length;
    final km = inPlan.fold<double>(0, (a, r) => a + r.distanceMeters / 1000);
    final secs = inPlan.fold<int>(0, (a, r) => a + r.movingTimeSeconds);
    Activity? longest;
    for (final a in inPlan) {
      if (longest == null || a.distanceMeters > longest.distanceMeters) longest = a;
    }
    final firstWeek = inPlan.where((a) => a.startedAt.isBefore(from.add(const Duration(days: 14)))).toList();
    final lastWeeks = inPlan.where((a) => a.startedAt.isAfter(to.subtract(const Duration(days: 14)))).toList();
    double avgPace(List<Activity> l) {
      final d = l.fold<double>(0, (a, r) => a + r.distanceMeters);
      return d <= 0 ? 0 : l.fold<int>(0, (a, r) => a + r.movingTimeSeconds) / (d / 1000);
    }

    final p0 = avgPace(firstWeek), p1 = avgPace(lastWeeks);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(colors: [RwColors.accent.withValues(alpha: 0.25), RwColors.surface], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: RwColors.accent.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SCHEMA AFGEROND', style: TextStyle(color: RwColors.accent, fontWeight: FontWeight.w800, letterSpacing: 0.6, fontSize: 12)),
            const SizedBox(height: 4),
            Text(doneCount >= sessions.length * 0.8 ? 'Wat een prestatie!' : 'Je bent er doorheen!',
                style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: StatTile(label: 'Trainingen', value: '$doneCount/${sessions.length}')),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Kilometers', value: km.round().toString())),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Tijd', value: '${(secs / 3600).toStringAsFixed(0)} u')),
            ]),
            const SizedBox(height: 10),
            if (longest != null)
              Text('Langste run: ${Fmt.km(longest.distanceMeters, decimals: 1)} op ${Fmt.date(longest.startedAt)}.', style: const TextStyle(color: RwColors.muted)),
            if (p0 > 0 && p1 > 0 && p0 - p1 >= 3)
              Text('Je gemiddelde tempo ging van ${Fmt.pace(p0)} naar ${Fmt.pace(p1)}.', style: const TextStyle(color: RwColors.good, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Klaar voor het volgende doel? Kies rechtsboven "Nieuw schema maken".', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

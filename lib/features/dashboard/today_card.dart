import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/heart_rate_service.dart';
import '../../data/services/sync_service.dart';
import '../../domain/race_forecast.dart';
import '../../domain/readiness.dart';
import '../../domain/training_load.dart';
import '../../domain/training_plan.dart';
import '../../domain/weekly_load.dart';
import '../../domain/weekly_report.dart';
import '../../shared/widgets.dart';
import '../activities/fitness_screen.dart';
import '../planner/training_plan_screen.dart';
import 'dashboard_providers.dart';

/// "Jij vandaag": training uit je schema, je klaar-score, herstel en vorm.
class TodayCard extends ConsumerWidget {
  const TodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final plan = ref.watch(planProvider).value ?? const <PlanSession>[];
    final body = ref.watch(bodySignalsProvider).value;
    final weather = ref.watch(forecastProvider).value?.at(DateTime.now());
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final session = plan.where((s) => s.date == today).firstOrNull;
    final next = plan.where((s) => s.date.isAfter(today)).firstOrNull;
    final doneToday = session != null &&
        sessionDone(session, [for (final a in runs) (start: a.startedAt, meters: a.distanceMeters, seconds: a.movingTimeSeconds)]);

    final maxHr = HeartRateService.instance.maxHr.value;
    final threshold = estimateThresholdPace(runs);
    final recent = [
      for (final a in runs)
        if (now.difference(a.startedAt).inHours < 96)
          (end: a.startedAt.add(Duration(seconds: a.movingTimeSeconds)), load: runLoad(a, thresholdPace: threshold, maxHr: maxHr)),
    ];
    final recovery = recoveryHours(recent, now);
    final series = runs.isEmpty ? const <FitnessDay>[] : fitnessSeries(runs, now, days: 1, maxHr: maxHr);
    final form = series.isEmpty ? null : formAdvice(series.last);
    final ready = readiness(body: body ?? const BodySignals(), recoveryHours: recovery, form: series.isEmpty ? null : series.last.form);
    final hardToday = session != null &&
        !doneToday &&
        (session.kind == SessionKind.tempo || session.kind == SessionKind.interval || session.kind == SessionKind.long);

    if (plan.isEmpty && runs.isEmpty) return const SizedBox.shrink();
    return RwCard(
      title: 'JIJ VANDAAG',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (runs.isNotEmpty) ...[
            _ReadinessRow(ready: ready, hasBody: body != null && !body.isEmpty),
            const Divider(height: 22),
          ],
          if (session != null) ...[
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: sessionColor(session.kind).withValues(alpha: 0.18),
                  child: doneToday
                      ? const Icon(Icons.check, color: RwColors.good)
                      : Icon(sessionIcon(session.kind), color: sessionColor(session.kind)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doneToday ? 'Gedaan: ${session.title}' : session.title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(session.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: RwColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
            if (hardToday && ready.suggestEasy && runs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: RwColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'Je klaar-score is ${ready.score}. Een stevige training kan vandaag beter een rustige worden.',
                  style: const TextStyle(color: RwColors.warning),
                ),
              ),
            ],
            if (!doneToday && session.kind != SessionKind.race) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => showSessionBriefing(context, hardToday && ready.suggestEasy ? easierSession(session) : session,
                    readinessScore: runs.isEmpty ? null : ready.score),
                icon: const Icon(Icons.play_arrow),
                label: Text(hardToday && ready.suggestEasy ? 'Start de rustige versie' : 'Start de training van vandaag'),
              ),
              if (session.kind != SessionKind.easy || !(hardToday && ready.suggestEasy))
                TextButton(
                  onPressed: () => hardToday && ready.suggestEasy
                      ? startSession(context, session, weather: weather)
                      : startSession(context, easierSession(session), weather: weather),
                  child: Text(hardToday && ready.suggestEasy ? 'Toch de gewone training' : 'Ik voel me niet 100%: maak het lichter'),
                ),
            ],
          ] else if (plan.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.hotel_outlined, color: RwColors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    next == null ? 'Je schema is klaar.' : 'Rustdag. Volgende: ${next.title} (${Fmt.date(next.date)}).',
                    style: const TextStyle(color: RwColors.muted),
                  ),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openTrainingPlan(context),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Maak een gratis trainingsschema'),
              ),
            ),
          if (plan.isNotEmpty) const PlanCheckCard(compact: true),
          if (runs.isNotEmpty) ...[
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                  child: _Mini(
                    icon: Icons.battery_charging_full,
                    label: 'Herstel',
                    value: recovery < 1 ? 'Hersteld' : 'nog ${recovery.round()} u',
                    color: recovery < 1 ? RwColors.good : (recovery > 36 ? RwColors.warning : RwColors.muted),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => openFitness(context),
                    child: _Mini(icon: Icons.show_chart, label: 'Vorm', value: form?.title ?? '–', color: RwColors.accent),
                  ),
                ),
                if (plan.isNotEmpty)
                  Expanded(
                    child: InkWell(
                      onTap: () => openTrainingPlan(context),
                      child: const _Mini(icon: Icons.calendar_month_outlined, label: 'Schema', value: 'Bekijk', color: RwColors.muted),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Color _scoreColor(int s) => s >= 75 ? RwColors.good : (s >= 50 ? RwColors.accent : (s >= 30 ? RwColors.warning : RwColors.danger));

class _ReadinessRow extends ConsumerWidget {
  const _ReadinessRow({required this.ready, required this.hasBody});
  final Readiness ready;
  final bool hasBody;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _scoreColor(ready.score);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _ReadinessSheet(ready: ready, hasBody: hasBody),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(value: ready.score / 100, strokeWidth: 5, color: color, backgroundColor: RwColors.bar),
                Text('${ready.score}', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Klaar-score', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
                Text(ready.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (!hasBody && Platform.isAndroid)
                  const Text('Tik om slaap en HRV van je horloge mee te nemen', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: RwColors.subtle),
        ],
      ),
    );
  }
}

class _ReadinessSheet extends ConsumerWidget {
  const _ReadinessSheet({required this.ready, required this.hasBody});
  final Readiness ready;
  final bool hasBody;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Klaar-score ${ready.score}', style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 22, fontWeight: FontWeight.w800)),
            Text(ready.title, style: TextStyle(color: _scoreColor(ready.score), fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final f in ready.factors)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(f.effect >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 18, color: f.effect >= 0 ? RwColors.good : RwColors.warning),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${f.label}: ${f.text}')),
                    Text(f.effect >= 0 ? '+${f.effect}' : '${f.effect}', style: const TextStyle(color: RwColors.subtle)),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            const Text(
              'De score begint bij 70 en gaat omhoog of omlaag door je slaap, rusthartslag en HRV (vergeleken met jouw normaal) '
              'en hoeveel herstel je nog nodig hebt. Het is een hulpmiddel: luister ook naar je lichaam.',
              style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.4),
            ),
            if (!hasBody && Platform.isAndroid) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await ref.read(syncServiceProvider).connectBody();
                  ref.invalidate(bodySignalsProvider);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  showMessage(
                    context,
                    ok
                        ? 'Gekoppeld. Draag je horloge of ring \'s nachts, dan telt je slaap en HRV mee.'
                        : 'Geen toestemming gekregen. Je kunt het later opnieuw proberen.',
                  );
                },
                icon: const Icon(Icons.bedtime_outlined),
                label: const Text('Slaap, rusthartslag en HRV koppelen'),
              ),
              const SizedBox(height: 4),
              const Text(
                'Via Health Connect (bijv. van Samsung Health, Garmin of Oura). Deze gegevens blijven op je telefoon.',
                style: TextStyle(color: RwColors.subtle, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: RwColors.subtle, fontSize: 11)),
                Text(value, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: color == RwColors.muted ? RwColors.text : color)),
              ],
            ),
          ),
        ],
      );
}

/// Weekoverzicht van vorige week, maandag t/m woensdag op Vandaag (wegklikbaar).
class WeeklyReportCard extends ConsumerStatefulWidget {
  const WeeklyReportCard({super.key});

  @override
  ConsumerState<WeeklyReportCard> createState() => _WeeklyReportCardState();
}

class _WeeklyReportCardState extends ConsumerState<WeeklyReportCard> {
  static const _key = 'weekly_report_dismissed';
  String? _dismissed;
  bool _loaded = false;

  String get _thisWeek {
    final w = weekStart(DateTime.now());
    return '${w.year}-${w.month}-${w.day}';
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _dismissed = p.getString(_key);
          _loaded = true;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = _thisWeek);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, _thisWeek);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    if (!_loaded || now.weekday > DateTime.wednesday || _dismissed == _thisWeek) return const SizedBox.shrink();
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    if (runs.isEmpty) return const SizedBox.shrink();
    final plan = ref.watch(planProvider).value ?? const <PlanSession>[];
    final r = weeklyReport(runs, now, plan: plan, maxHr: HeartRateService.instance.maxHr.value);
    final diff = r.avgKmBefore <= 0 ? null : (r.km - r.avgKmBefore) / r.avgKmBefore;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RwCard(
        title: 'JE VORIGE WEEK',
        trailing: IconButton(
          tooltip: 'Verbergen tot volgende week',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 18),
          onPressed: _dismiss,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(r.headline, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _Stat(label: 'Kilometers', value: r.km.toStringAsFixed(1).replaceAll('.', ','))),
                Expanded(child: _Stat(label: 'Runs', value: '${r.runs}')),
                Expanded(child: _Stat(label: 'Tijd', value: Fmt.duration(r.seconds))),
              ],
            ),
            const SizedBox(height: 10),
            if (diff != null)
              _Line(
                icon: diff >= 0 ? Icons.trending_up : Icons.trending_down,
                text: '${diff >= 0 ? '+' : ''}${(diff * 100).round()}% ten opzichte van je gemiddelde (${r.avgKmBefore.toStringAsFixed(1).replaceAll('.', ',')} km per week)',
              ),
            if (r.planTotal != null)
              _Line(icon: Icons.calendar_month_outlined, text: 'Schema: ${r.planDone} van ${r.planTotal} trainingen gedaan'),
            if (r.longest != null)
              _Line(icon: Icons.route_outlined, text: 'Langste run: ${Fmt.km(r.longest!.distanceMeters, decimals: 1)} op ${Fmt.date(r.longest!.startedAt)}'),
            if (r.easyShare != null)
              _Line(
                icon: Icons.balance,
                text: '${(r.easyShare! * 100).round()}% rustig gelopen${r.easyShare! < 0.6 ? ' – maak een paar runs rustiger' : ''}',
              ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: RwColors.subtle, fontSize: 11)),
          Text(value, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: 20)),
        ],
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: RwColors.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(color: RwColors.muted))),
          ],
        ),
      );
}

/// Aftellen naar je volgende wedstrijd, met verwachte tijd tegenover je doel (zoals de wedstrijdwidget van Garmin).
class RaceCountdownCard extends ConsumerWidget {
  const RaceCountdownCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final races = ref.watch(racesProvider).value ?? const <RaceEvent>[];
    final upcoming = races.where((r) => r.daysUntil >= 0 && r.daysUntil <= 120).toList()
      ..sort((a, b) => a.raceDate.compareTo(b.raceDate));
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final race = upcoming.first;
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final advice = adviseRace(race: race, activities: runs, profile: ref.watch(insightsProvider));
    final predicted = advice.baseFinishSeconds;
    final diff = predicted - race.goalTimeSeconds;
    final days = race.daysUntil;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RwCard(
        onTap: race.id == null ? null : () => context.go('/me/races/${race.id}'),
        child: Row(
          children: [
            Container(
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: RwColors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  Text(days == 0 ? '!' : '$days',
                      style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: 26, color: RwColors.accent, height: 1)),
                  Text(days == 0 ? 'vandaag' : (days == 1 ? 'dag' : 'dagen'), style: const TextStyle(color: RwColors.accent, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(race.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('${Fmt.km(race.distanceMeters, decimals: 1)} · ${Fmt.date(race.raceDate)}', style: const TextStyle(color: RwColors.subtle, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Verwacht ', style: TextStyle(color: RwColors.muted)),
                    TextSpan(text: Fmt.duration(predicted), style: const TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(
                      text: diff.abs() < 15
                          ? ' · precies je doel'
                          : (diff < 0 ? ' · ${Fmt.duration(-diff)} sneller dan je doel' : ' · ${Fmt.duration(diff)} boven je doel'),
                      style: TextStyle(color: diff <= 15 ? RwColors.good : RwColors.warning, fontWeight: FontWeight.w600),
                    ),
                  ])),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: RwColors.subtle),
          ],
        ),
      ),
    );
  }
}

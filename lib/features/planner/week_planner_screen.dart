import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/weather_service.dart';
import '../../domain/availability.dart';
import '../../domain/performance_model.dart';
import '../../domain/start_time_scoring.dart';
import '../../shared/widgets.dart';
import '../dashboard/dashboard_providers.dart';
import 'availability_provider.dart';

void openWeekPlanner(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WeekPlannerScreen()));
}

/// Kaartje op Vandaag dat naar de weekplanner leidt.
class WeekPlannerEntry extends ConsumerWidget {
  const WeekPlannerEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(availabilityProvider).value ?? Availability.always;
    return RwCard(
      title: 'WEEKPLANNER',
      onTap: () => openWeekPlanner(context),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: RwColors.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.calendar_month_outlined, color: RwColors.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              a.isAlways
                  ? 'De beste dag voor je duurloop en je intervallen, de komende 7 dagen. Stel ook in wanneer je kunt lopen.'
                  : 'De beste dag voor elke training, binnen jouw looptijden.',
              style: const TextStyle(height: 1.4),
            ),
          ),
          const Icon(Icons.chevron_right, color: RwColors.subtle),
        ],
      ),
    );
  }
}

/// Beste moment per dag en per soort training, voor de komende 7 dagen.
class _DayPlan {
  _DayPlan(this.day, this.easy, this.quality, this.long);
  final DateTime day;
  final StartTimeScore? easy;
  final StartTimeScore? quality;
  final StartTimeScore? long;
}

List<_DayPlan> _plan(Forecast f, PerformanceInsights profile, Availability availability) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  StartTimeScore? bestOn(DateTime day, TrainingType type, int minutes) {
    final start = day.isAfter(now) ? day : now;
    final end = DateTime(day.year, day.month, day.day, 22, 30);
    if (!end.isAfter(start)) return null;
    return StartTimePlanner(forecast: f, profile: profile, durationMinutes: minutes, availability: availability)
        .bestPrecise(type, from: start, horizon: end.difference(start), stepMinutes: 15);
  }

  return [
    for (var i = 0; i < 7; i++)
      () {
        final d = today.add(Duration(days: i));
        return _DayPlan(d, bestOn(d, TrainingType.easy, 45), bestOn(d, TrainingType.quality, 50), bestOn(d, TrainingType.long, 90));
      }(),
  ];
}

class WeekPlannerScreen extends ConsumerWidget {
  const WeekPlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecast = ref.watch(weekForecastProvider);
    final availability = ref.watch(availabilityProvider).value ?? Availability.always;
    final insights = ref.watch(insightsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Weekplanner')),
      body: forecast.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(weekForecastProvider)),
        data: (f) {
          final days = _plan(f, insights, availability);
          StartTimeScore? top(StartTimeScore? Function(_DayPlan) pick) {
            StartTimeScore? best;
            for (final d in days) {
              final s = pick(d);
              if (s != null && (best == null || s.score > best.score)) best = s;
            }
            return best;
          }

          final bestLong = top((d) => d.long);
          final bestQuality = top((d) => d.quality);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              RwCard(
                title: 'WANNEER KUN JE LOPEN?',
                onTap: () => _editAvailability(context, ref, availability),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        availability.isAlways ? 'Elke dag tussen 05:00 en 22:00. Tik om je eigen tijden in te stellen, ook voor wisseldiensten.' : availability.summary,
                        style: const TextStyle(height: 1.45),
                      ),
                    ),
                    const Icon(Icons.edit_outlined, color: RwColors.subtle),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              RwCard(
                title: 'AANRADERS DEZE WEEK',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Pick(label: 'Lange duurloop (90 min)', score: bestLong),
                    const SizedBox(height: 10),
                    _Pick(label: 'Tempo of intervallen', score: bestQuality),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final d in days) ...[
                _DayCard(plan: d),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              const Text(
                'Verder vooruit is de verwachting minder zeker. Kijk de dag zelf op Vandaag voor het moment op 5 minuten nauwkeurig.',
                style: TextStyle(color: RwColors.subtle, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editAvailability(BuildContext context, WidgetRef ref, Availability current) async {
    final next = await Navigator.of(context).push<Availability>(
      MaterialPageRoute(builder: (_) => AvailabilityScreen(initial: current)),
    );
    if (next != null) await saveAvailability(ref, next);
  }
}

String _day(DateTime d) {
  final now = DateTime.now();
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (diff == 0) return 'Vandaag';
  if (diff == 1) return 'Morgen';
  return _cap(DateFormat('EEEE d MMM', 'nl_NL').format(d));
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

Color _color(int score) => score >= 70 ? RwColors.good : (score >= 45 ? RwColors.warning : RwColors.danger);

class _Pick extends StatelessWidget {
  const _Pick({required this.label, required this.score});
  final String label;
  final StartTimeScore? score;

  @override
  Widget build(BuildContext context) {
    final s = score;
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: RwColors.muted))),
        Text(
          s == null ? 'geen moment' : '${_day(s.start)} ${Fmt.time(s.start)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (s != null) ...[
          const SizedBox(width: 8),
          Text('${s.score}', style: TextStyle(color: _color(s.score), fontWeight: FontWeight.w800)),
        ],
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.plan});
  final _DayPlan plan;

  @override
  Widget build(BuildContext context) {
    final e = plan.easy;
    return RwCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_day(plan.day), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 3),
                Text(
                  e == null
                      ? 'Geen moment binnen je looptijden'
                      : '${weatherLabel(e.weather.weatherCode)} · ${Fmt.temp(e.weather.feelsLike ?? e.weather.temperature)} · wind ${Fmt.wind(e.weather.windSpeed)}',
                  style: const TextStyle(color: RwColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (e != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.time(e.start),
                    style: const TextStyle(fontFamily: RwFonts.display, fontSize: 24, fontWeight: FontWeight.w800, color: RwColors.accent)),
                Text('score ${e.score}', style: TextStyle(color: _color(e.score), fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Instellen wanneer je kunt lopen: per dag aan/uit en van–tot.
class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key, required this.initial});
  final Availability initial;

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  late final Map<int, TimeWindow?> _days = {
    for (var d = 1; d <= 7; d++)
      d: widget.initial.isAlways
          ? const TimeWindow(5 * 60, 22 * 60)
          : ((widget.initial.days[d] ?? const []).isEmpty ? null : widget.initial.days[d]!.first),
  };

  void _preset(String name) {
    final a = Availability.preset(name);
    setState(() {
      for (var d = 1; d <= 7; d++) {
        _days[d] = a.isAlways ? const TimeWindow(5 * 60, 22 * 60) : ((a.days[d] ?? const []).isEmpty ? null : a.days[d]!.first);
      }
    });
  }

  Future<void> _pick(int day, bool start) async {
    final w = _days[day] ?? const TimeWindow(17 * 60, 21 * 60);
    final m = start ? w.startMinute : w.endMinute;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
    if (t == null) return;
    final v = t.hour * 60 + t.minute;
    setState(() {
      if (start) {
        _days[day] = TimeWindow(v, v + 30 > w.endMinute ? (v + 60).clamp(0, 24 * 60) : w.endMinute);
      } else {
        _days[day] = TimeWindow(v - 30 < w.startMinute ? (v - 60).clamp(0, 24 * 60) : w.startMinute, v);
      }
    });
  }

  Availability _result() {
    final allDay = _days.values.every((w) => w != null && w.startMinute == 5 * 60 && w.endMinute == 22 * 60);
    if (allDay) return Availability.always;
    return Availability({for (final e in _days.entries) e.key: e.value == null ? const [] : [e.value!]});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mijn looptijden'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, _result()), child: const Text('Opslaan'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'RunWise kiest alleen momenten waarop je hele run binnen deze tijden past. Werk je in wisseldiensten? Pas het per week aan.',
            style: TextStyle(color: RwColors.muted, height: 1.45),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(label: const Text('Altijd'), onPressed: () => _preset('altijd')),
            ActionChip(label: const Text('Na werk + weekend'), onPressed: () => _preset('werk')),
            ActionChip(label: const Text('Alleen ochtend'), onPressed: () => _preset('ochtend')),
            ActionChip(label: const Text('Alleen avond'), onPressed: () => _preset('avond')),
          ]),
          const SizedBox(height: 12),
          for (var d = 1; d <= 7; d++)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(_cap(Availability.dayNames[d - 1]),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: _days[d] == null
                          ? const Text('kan niet', style: TextStyle(color: RwColors.subtle))
                          : Row(children: [
                              TextButton(onPressed: () => _pick(d, true), child: Text(TimeWindow.fmt(_days[d]!.startMinute))),
                              const Text('–'),
                              TextButton(onPressed: () => _pick(d, false), child: Text(TimeWindow.fmt(_days[d]!.endMinute))),
                            ]),
                    ),
                    Switch(
                      value: _days[d] != null,
                      onChanged: (on) => setState(() => _days[d] = on ? const TimeWindow(17 * 60, 21 * 60) : null),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/location_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/geo.dart';
import '../../domain/race_forecast.dart';
import '../../domain/start_time_scoring.dart';
import '../../domain/zones.dart';
import '../../shared/flip_digits.dart';
import '../../shared/widgets.dart';
import '../dashboard/dashboard_providers.dart';
import 'pace_band.dart';

/// Alles wat nodig is voor het wedstrijdadvies.
final _raceAdviceProvider = FutureProvider.family<RaceAdvice, String>((ref, raceId) async {
  final race = await ref.watch(raceDetailProvider(raceId).future);
  final activities = await ref.watch(activitiesProvider.future);
  final profile = ref.watch(insightsProvider);

  RunRoute? route;
  if (race.routeId != null) {
    try {
      route = await ref.watch(routeDetailProvider(race.routeId!).future);
    } catch (_) {
      route = null;
    }
  }

  Forecast? forecast;
  RouteWind? wind;
  final days = race.daysUntil;
  if (days >= 0 && days <= forecastHorizonDays) {
    double lat, lon;
    if (race.startLatitude != null && race.startLongitude != null) {
      lat = race.startLatitude!;
      lon = race.startLongitude!;
    } else {
      final loc = await ref.watch(weatherLocationProvider.future);
      lat = loc.latitude;
      lon = loc.longitude;
    }
    forecast = await ref.watch(weatherServiceProvider).forecast(lat, lon, days: days + 1);
    final w = forecast.at(race.startDateTime);
    if (route != null && w != null && w.windDirection != null) {
      wind = routeWind(trackSegments(decodePolyline(route.polyline)), w.windSpeed, w.windDirection!);
    }
  }

  return adviseRace(
    race: race,
    activities: activities,
    profile: profile,
    forecast: forecast,
    routeWind: wind,
  );
});

class RaceDetailScreen extends ConsumerWidget {
  const RaceDetailScreen({super.key, required this.raceId});
  final String raceId;

  Future<void> _delete(BuildContext context, WidgetRef ref, RaceEvent race) async {
    final ok = await confirmDialog(
      context,
      title: 'Wedstrijd verwijderen?',
      message: '"${race.name}" wordt verwijderd.',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteRace(race.id!);
      ref.invalidate(racesProvider);
      if (context.mounted) context.go('/me/races');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final race = ref.watch(raceDetailProvider(raceId));
    final advice = ref.watch(_raceAdviceProvider(raceId));

    return race.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(raceDetailProvider(raceId))),
      ),
      data: (r) => Scaffold(
        appBar: AppBar(
          title: Text(r.name, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Verwijderen',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref, r),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async => ref.invalidate(_raceAdviceProvider(raceId)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                '${Fmt.dateLong(r.raceDate)}${r.startTime == null ? '' : ' · start ${r.startTime}'}',
                style: TextStyle(color: RwColors.muted),
              ),
              if (r.daysUntil > 0) ...[
                const SizedBox(height: 14),
                // Groot klapbord: dagen tot de start.
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  FlipDigits(text: '${r.daysUntil}', size: 1.7),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(r.daysUntil == 1 ? 'dag tot de start' : 'dagen tot de start',
                        style: TextStyle(color: RwColors.muted, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ] else
              const SizedBox(height: 4),
              if (r.daysUntil <= 0)
              Text(
                r.daysUntil > 0
                    ? 'Nog ${r.daysUntil} dagen'
                    : r.daysUntil == 0
                        ? 'Het is vandaag. Succes!'
                        : 'Deze wedstrijd is geweest',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, fontFamily: RwFonts.display, fontFeatures: rwTnum),
              ),
              const SizedBox(height: 16),
              advice.when(
                loading: () => const Padding(padding: EdgeInsets.all(40), child: LoadingView(spinner: true)),
                error: (e, _) => ErrorView(
                  message: friendlyError(e),
                  onRetry: () => ref.invalidate(_raceAdviceProvider(raceId)),
                ),
                data: (a) => _AdviceView(race: r, advice: a),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdviceView extends StatelessWidget {
  const _AdviceView({required this.race, required this.advice});
  final RaceEvent race;
  final RaceAdvice advice;

  @override
  Widget build(BuildContext context) {
    final predicted = advice.predictedFinishSeconds;
    final vsGoal = predicted - race.goalTimeSeconds;
    final w = advice.weather;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RwCard(
          title: 'VERWACHTE EINDTIJD',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Fmt.duration(predicted),
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: RwColors.accent, fontFamily: RwFonts.display, fontFeatures: rwTnum),
              ),
              Text(
                vsGoal.abs() < 15
                    ? 'Precies rond je doeltijd van ${Fmt.duration(race.goalTimeSeconds)}.'
                    : vsGoal < 0
                        ? '${Fmt.duration(-vsGoal)} sneller dan je doel van ${Fmt.duration(race.goalTimeSeconds)}.'
                        : '${Fmt.duration(vsGoal)} langzamer dan je doel van ${Fmt.duration(race.goalTimeSeconds)}.',
                style: TextStyle(color: RwColors.muted),
              ),
              const SizedBox(height: 12),
              _Line('Basis', advice.basedOn, Fmt.duration(advice.baseFinishSeconds)),
              if (w != null) ...[
                _Line('Temperatuur', 'Gevoel ${Fmt.temp(w.feelsLike ?? w.temperature)}',
                    Fmt.signedDuration(advice.temperatureImpactSeconds)),
                _Line('Wind', '${Fmt.wind(w.windSpeed)}${w.windDirection == null ? '' : ' uit ${Fmt.compass(w.windDirection!)}'}',
                    Fmt.signedDuration(advice.windImpactSeconds)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (w == null)
          RwCard(
            title: 'WEER OP DE WEDSTRIJDDAG',
            child: Text(
              race.daysUntil < 0
                  ? 'Deze wedstrijd is al geweest.'
                  : 'De weersverwachting komt ongeveer $forecastHorizonDays dagen van tevoren beschikbaar. '
                      'Kom dan terug voor een voorspelling met het weer erbij.',
              style: TextStyle(height: 1.5, color: RwColors.muted),
            ),
          )
        else
          RwCard(
            title: 'WEER BIJ DE START',
            child: Row(
              children: [
                Expanded(child: StatTile(label: 'Gevoel', value: Fmt.temp(w.feelsLike ?? w.temperature))),
                const SizedBox(width: 8),
                Expanded(child: StatTile(label: 'Wind', value: Fmt.wind(w.windSpeed))),
                const SizedBox(width: 8),
                Expanded(child: StatTile(label: 'Regen', value: Fmt.pct(w.precipitationProbability))),
              ],
            ),
          ),
        const SizedBox(height: 12),
        _AdviceCard(icon: Icons.speed, title: 'Tempo', text: advice.pacing),
        const SizedBox(height: 12),
        _PacingCard(race: race),
        const SizedBox(height: 12),
        _AdviceCard(icon: Icons.checkroom_outlined, title: 'Kleding', text: advice.clothing),
        const SizedBox(height: 12),
        _AdviceCard(icon: Icons.water_drop_outlined, title: 'Drinken en energie', text: advice.hydration),
        const SizedBox(height: 12),
        Text(
          'Dit is een schatting op basis van je runs en het verwachte weer, geen garantie. '
          'Luister naar je lichaam.',
          style: TextStyle(color: RwColors.subtle, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.detail, this.value);
  final String label;
  final String detail;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 96, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(detail, style: TextStyle(color: RwColors.subtle))),
            Text(value),
          ],
        ),
      );
}

class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => RwCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: RwColors.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(text, style: TextStyle(color: RwColors.muted, height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Tempoplan: tijd per kilometer om precies op je doeltijd uit te komen.
class _PacingCard extends StatefulWidget {
  const _PacingCard({required this.race});
  final RaceEvent race;

  @override
  State<_PacingCard> createState() => _PacingCardState();
}

class _PacingCardState extends State<_PacingCard> {
  PacingStrategy _strategy = PacingStrategy.easyStart;
  bool _all = false;

  Future<void> _shareBand(List<PlannedSplit> plan) async {
    final r = widget.race;
    try {
      final png = await paceBandPng(
        title: r.name,
        subtitle: '${Fmt.km(r.distanceMeters, decimals: 1)} · doel ${Fmt.duration(r.goalTimeSeconds)} · ${_strategy.label.toLowerCase()}',
        plan: plan,
      );
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png', name: 'tempoband.png')],
        subject: 'Tempoband ${r.name}',
      ));
    } catch (_) {
      if (mounted) showMessage(context, 'Het tempobandje kon niet worden gemaakt.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.race;
    final plan = pacingPlan(r.distanceMeters, r.goalTimeSeconds, _strategy);
    if (plan.isEmpty) return const SizedBox.shrink();
    final shown = _all || plan.length <= 12 ? plan : [...plan.take(5), ...plan.skip(plan.length - 3)];
    return RwCard(
      title: 'TEMPOPLAN PER KM',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<PacingStrategy>(
            showSelectedIcon: false,
            segments: [for (final p in PacingStrategy.values) ButtonSegment(value: p, label: Text(p.label, style: const TextStyle(fontSize: 12)))],
            selected: {_strategy},
            onSelectionChanged: (x) => setState(() => _strategy = x.first),
          ),
          const SizedBox(height: 6),
          Text(
            switch (_strategy) {
              PacingStrategy.even => 'Elke kilometer even snel. Simpel, maar zwaar als je te snel start.',
              PacingStrategy.negative => 'Eerste helft iets rustiger, tweede helft iets sneller. Vaak het snelst.',
              PacingStrategy.easyStart => 'De eerste 2 km rustiger (in de drukte), daarna op doeltempo.',
            },
            style: TextStyle(color: RwColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          for (final (i, sp) in shown.indexed) ...[
            if (!_all && plan.length > 12 && i == 5)
              Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Text('…', style: TextStyle(color: RwColors.subtle))),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 56, child: Text(sp.meters < 999 ? '${(sp.km - 1 + sp.meters / 1000).toStringAsFixed(1).replaceAll('.', ',')}' : 'km ${sp.km}', style: TextStyle(color: RwColors.subtle))),
                Expanded(child: Text(Fmt.pace(sp.pace), style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(Fmt.duration(sp.cumulative.round()), style: TextStyle(color: RwColors.muted)),
              ]),
            ),
          ],
          if (plan.length > 12)
            TextButton(onPressed: () => setState(() => _all = !_all), child: Text(_all ? 'Minder tonen' : 'Alle ${plan.length} km tonen')),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => _shareBand(plan),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Tempobandje delen of printen'),
          ),
        ],
      ),
    );
  }
}

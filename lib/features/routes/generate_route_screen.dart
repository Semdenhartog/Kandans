import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/location_service.dart';
import '../../data/services/route_generator_service.dart';
import '../../data/services/sync_service.dart';
import '../../domain/geo.dart';
import '../../domain/gpx_parser.dart';
import '../../domain/route_direction.dart';
import '../../domain/start_time_scoring.dart';
import '../../shared/widgets.dart';
import '../dashboard/dashboard_providers.dart';
import 'route_map.dart';
import 'route_map_screen.dart';

/// Een voorgesteld rondje met het beste vertrekmoment en de beste looprichting.
class _Candidate {
  _Candidate({required this.route, required this.best, required this.directionLabel});
  final RunRoute route;
  final StartTimeScore best;
  final String? directionLabel;
}

class GenerateRouteScreen extends ConsumerStatefulWidget {
  const GenerateRouteScreen({super.key});

  @override
  ConsumerState<GenerateRouteScreen> createState() => _GenerateRouteScreenState();
}

class _GenerateRouteScreenState extends ConsumerState<GenerateRouteScreen> {
  final _address = TextEditingController();
  bool _useMyLocation = true;
  Place? _place;
  List<Place> _suggestions = const [];
  bool _searching = false;

  bool _byTime = false;
  double _km = 8;
  int _minutes = 45;

  bool _busy = false;
  List<_Candidate> _results = const [];
  String? _saving;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  /// Gemiddeld tempo van je laatste runs (standaard 6:00/km).
  double _pace() {
    final runs = ref.read(activitiesProvider).value ?? const <Activity>[];
    final recent = runs.take(10).where((a) => a.paceSecondsPerKm > 0).toList();
    if (recent.isEmpty) return 360;
    return recent.fold<double>(0, (s, a) => s + a.paceSecondsPerKm) / recent.length;
  }

  double get _targetMeters => _byTime ? _minutes * 60 / _pace() * 1000 : _km * 1000;

  Future<void> _search() async {
    setState(() => _searching = true);
    try {
      final list = await ref.read(routeGeneratorProvider).searchAddress(_address.text);
      setState(() => _suggestions = list);
      if (list.isEmpty && mounted) showMessage(context, 'Geen adres gevonden. Probeer straat, huisnummer en plaats.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _generate() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _results = const [];
    });
    try {
      final double lat, lon;
      final String startLabel;
      if (_useMyLocation) {
        // Je koos zelf "Mijn locatie": dan mag de app om toestemming vragen.
        if (!await locationExplained()) {
          await markLocationExplained();
          ref.invalidate(weatherLocationProvider);
        }
        final loc = await ref.read(weatherLocationProvider.future);
        lat = loc.latitude;
        lon = loc.longitude;
        startLabel = 'huis';
      } else {
        final p = _place;
        if (p == null) throw Exception('Kies eerst een startadres.');
        lat = p.lat;
        lon = p.lon;
        startLabel = p.label.split(',').first;
      }

      final loops = await ref.read(routeGeneratorProvider).generate(lat, lon, _targetMeters);
      final forecast = await ref.read(forecastProvider.future);
      final profile = ref.read(insightsProvider);
      final pace = _pace();

      final candidates = <_Candidate>[];
      for (final loop in loops) {
        _Candidate? bestOfTwo;
        for (final reversed in [false, true]) {
          final pts = reversed ? loop.points.reversed.toList() : loop.points;
          final km = (loop.distanceMeters / 1000).toStringAsFixed(1).replaceAll('.', ',');
          final route = buildRoute(pts, name: 'Rondje $km km vanaf $startLabel', source: 'generated', estimatedPaceSecPerKm: pace);
          final track = decodePolyline(route.polyline);
          final planner = StartTimePlanner(
            forecast: forecast,
            profile: profile,
            track: track,
            durationMinutes: ((route.estimatedDurationSeconds ?? 2700) / 60).round(),
          );
          final best = planner.bestPrecise(TrainingType.easy);
          if (best == null) continue;
          final cand = _Candidate(
            route: route,
            best: best,
            directionLabel: isLoop(track) ? (signedArea(track) > 0 ? 'linksom' : 'rechtsom') : null,
          );
          if (bestOfTwo == null || cand.best.score > bestOfTwo.best.score) bestOfTwo = cand;
        }
        if (bestOfTwo != null) candidates.add(bestOfTwo);
      }
      final target = _targetMeters;
      candidates.sort((a, b) {
        final s = b.best.score.compareTo(a.best.score);
        if (s != 0) return s;
        return (a.route.distanceMeters - target).abs().compareTo((b.route.distanceMeters - target).abs());
      });
      setState(() => _results = candidates.take(3).toList());
      if (candidates.isEmpty && mounted) showMessage(context, 'Geen geschikt rondje gevonden. Kies een ander startpunt.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(_Candidate c) async {
    setState(() => _saving = c.route.polyline);
    try {
      final id = await ref.read(repositoryProvider).addRoute(c.route);
      ref.invalidate(routesProvider);
      final linked = await ref.read(syncServiceProvider).autoLinkRuns().catchError((_) => 0);
      if (!mounted) return;
      showMessage(
        context,
        linked > 0
            ? 'Route opgeslagen. $linked eerdere ${linked == 1 ? 'run' : 'runs'} op dit rondje gekoppeld.'
            : 'Route opgeslagen.',
      );
      context.go('/routes/$id?nieuw=1');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pace = _pace();
    return Scaffold(
      appBar: AppBar(title: const Text('Route maken')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          RwCard(
            title: 'STARTPUNT',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Mijn locatie'), icon: Icon(Icons.my_location)),
                    ButtonSegment(value: false, label: Text('Adres'), icon: Icon(Icons.place_outlined)),
                  ],
                  selected: {_useMyLocation},
                  onSelectionChanged: (s) => setState(() => _useMyLocation = s.first),
                ),
                if (!_useMyLocation) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _address,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      labelText: 'Straat, huisnummer en plaats',
                      suffixIcon: IconButton(
                        tooltip: 'Zoeken',
                        icon: _searching
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.search),
                        onPressed: _searching ? null : _search,
                      ),
                    ),
                  ),
                  if (_place != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: RwColors.good, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_place!.label)),
                        ],
                      ),
                    ),
                  for (final p in _suggestions)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.place_outlined, color: RwColors.subtle),
                      title: Text(p.label),
                      onTap: () => setState(() {
                        _place = p;
                        _address.text = p.label;
                        _suggestions = const [];
                      }),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          RwCard(
            title: 'HOE VER OF HOE LANG',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Afstand')),
                    ButtonSegment(value: true, label: Text('Tijd')),
                  ],
                  selected: {_byTime},
                  onSelectionChanged: (s) => setState(() => _byTime = s.first),
                ),
                const SizedBox(height: 16),
                Text(
                  _byTime ? Fmt.duration(_minutes * 60) : '${_km.toStringAsFixed(_km % 1 == 0 ? 0 : 1).replaceAll('.', ',')} km',
                  style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 40, fontWeight: FontWeight.w800, color: RwColors.accent),
                ),
                Text(
                  _byTime
                      ? 'Ongeveer ${Fmt.km(_targetMeters, decimals: 1)} bij jouw tempo van ${Fmt.pace(pace)}'
                      : 'Ongeveer ${Fmt.duration((_km * pace).round())} bij jouw tempo van ${Fmt.pace(pace)}',
                  style: const TextStyle(color: RwColors.muted),
                ),
                if (_byTime)
                  Slider(
                    value: _minutes.toDouble(),
                    min: 15,
                    max: 180,
                    divisions: 33,
                    label: '$_minutes min',
                    onChanged: (v) => setState(() => _minutes = v.round()),
                  )
                else
                  Slider(
                    value: _km,
                    min: 2,
                    max: 30,
                    divisions: 56,
                    label: '${_km.toStringAsFixed(1)} km',
                    onChanged: (v) => setState(() => _km = v),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _generate,
            icon: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: RwColors.accentDark))
                : const Icon(Icons.auto_awesome),
            label: Text(_busy ? 'Rondjes zoeken…' : 'Maak mijn route'),
          ),
          const SizedBox(height: 8),
          const Text(
            'RunWise maakt een paar rondjes over wandel- en hardlooppaden en kiest de beste op de wind van vandaag.',
            textAlign: TextAlign.center,
            style: TextStyle(color: RwColors.subtle, fontSize: 13),
          ),
          for (final (i, c) in _results.indexed) ...[
            const SizedBox(height: 12),
            _CandidateCard(
              candidate: c,
              recommended: i == 0,
              saving: _saving == c.route.polyline,
              onSave: () => _save(c),
            ),
          ],
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Routes © openrouteservice.org · kaartgegevens © OpenStreetMap-bijdragers',
              textAlign: TextAlign.center,
              style: TextStyle(color: RwColors.subtle, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate, required this.recommended, required this.saving, required this.onSave});
  final _Candidate candidate;
  final bool recommended;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final r = candidate.route;
    final b = candidate.best;
    return RwCard(
      title: recommended ? 'BESTE KEUZE' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: RouteMap(
              polyline: r.polyline,
              windSpeedKmh: b.weather.windSpeed,
              windFromDegrees: b.weather.windDirection,
              compact: true,
              interactive: false,
              onExpand: () => openRouteMap(
                context,
                RouteMapData(
                  title: r.name,
                  polyline: r.polyline,
                  distanceMeters: r.distanceMeters,
                  windSpeedKmh: b.weather.windSpeed,
                  windFromDegrees: b.weather.windDirection,
                  profile: r.elevationProfile,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${Fmt.km(r.distanceMeters, decimals: 1)} · ${(r.elevationGainMeters ?? 0).round()} hm',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Beste vertrektijd ${Fmt.time(b.start)} · score ${b.score}',
                      style: const TextStyle(color: RwColors.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Kleuren op de kaart: de wind om ${Fmt.time(b.start)}',
                      style: const TextStyle(color: RwColors.subtle, fontSize: 12),
                    ),
                    if (candidate.directionLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Loop ${candidate.directionLabel}: zo heb je de minste tegenwind op het eind',
                        style: const TextStyle(color: RwColors.subtle, fontSize: 13, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recommended)
            FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Route opslaan'),
            )
          else
            OutlinedButton.icon(
              onPressed: saving ? null : onSave,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Route opslaan'),
            ),
        ],
      ),
    );
  }
}

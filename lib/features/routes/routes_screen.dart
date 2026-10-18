import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/geo.dart';
import '../../domain/gpx_parser.dart';
import '../../domain/start_time_scoring.dart';
import '../../shared/rw_components.dart';
import '../../shared/widgets.dart';
import '../dashboard/dashboard_providers.dart';

enum _Filter { alles, k5, k10, k15, favorieten }

extension on _Filter {
  String get label => switch (this) {
        _Filter.alles => 'Alles',
        _Filter.k5 => '5 km',
        _Filter.k10 => '10 km',
        _Filter.k15 => '15 km+',
        _Filter.favorieten => 'Favorieten',
      };

  bool matches(RunRoute r) {
    final km = r.distanceMeters / 1000;
    return switch (this) {
      _Filter.alles => true,
      _Filter.k5 => km < 7.5,
      _Filter.k10 => km >= 7.5 && km < 12.5,
      _Filter.k15 => km >= 12.5,
      _Filter.favorieten => r.isFavorite,
    };
  }
}

/// Routes-scherm volgens het Figma-ontwerp.
class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  bool _importing = false;
  _Filter _filter = _Filter.alles;
  bool _sortByDistance = false;

  Future<void> _importGpx() async {
    setState(() => _importing = true);
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null) return;
      if (!file.name.toLowerCase().endsWith('.gpx')) {
        throw GpxParseException('Kies een .gpx-bestand.');
      }
      final bytes = await file.readAsBytes();
      final route = parseGpx(
        utf8.decode(bytes, allowMalformed: true),
        fallbackName: file.name.replaceAll(RegExp(r'\.gpx$', caseSensitive: false), ''),
        estimatedPaceSecPerKm: ref.read(typicalPaceProvider),
      );
      final id = await ref.read(repositoryProvider).addRoute(route);
      ref.invalidate(routesProvider);
      if (!mounted) return;
      showMessage(context, 'Route "${route.name}" toegevoegd (${Fmt.km(route.distanceMeters, decimals: 1)}).');
      context.go('/routes/$id');
    } on GpxParseException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(routesProvider);
    final scores = ref.watch(routeScoresProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(routesProvider);
            ref.invalidate(forecastProvider);
            try {
              await ref.read(routeScoresProvider.future);
            } catch (_) {
              // Fout wordt in het scherm getoond.
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              PageHeader(
                title: 'Routes',
                subtitle: 'Rondjes vanaf huis, gesorteerd op score',
                action: _importing
                    ? const SizedBox(width: 44, height: 44, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2.5)))
                    : RoundIconButton(icon: Icons.add, filled: true, onTap: _importGpx, tooltip: 'GPX importeren'),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    RoundIconButton(
                      icon: Icons.tune,
                      size: 36,
                      iconSize: 18,
                      tooltip: 'Sorteren',
                      onTap: () {
                        setState(() => _sortByDistance = !_sortByDistance);
                        showMessage(context, _sortByDistance ? 'Gesorteerd op afstand' : 'Gesorteerd op score');
                      },
                    ),
                    for (final f in _Filter.values) ...[
                      const SizedBox(width: 8),
                      RwChip(label: f.label, active: f == _filter, onTap: () => setState(() => _filter = f)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              routes.when(
                loading: () => const Padding(padding: EdgeInsets.only(top: 60), child: LoadingView()),
                error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(routesProvider)),
                data: (list) {
                  if (list.isEmpty) {
                    return EmptyState(
                      icon: Icons.route,
                      title: 'Nog geen routes',
                      message: 'Importeer een GPX-bestand van je vaste rondje, bijvoorbeeld uit Strava, '
                          'Garmin of Komoot. RunWise rekent dan met de wind op jouw looprichting.',
                      actionLabel: 'GPX importeren',
                      onAction: _importGpx,
                    );
                  }
                  final scored = scores.when(
                    data: (s) => s,
                    loading: () => list.map((r) => RouteScore(r, null)).toList(),
                    error: (_, _) => list.map((r) => RouteScore(r, null)).toList(),
                  );
                  final shown = scored.where((s) => _filter.matches(s.route)).toList();
                  if (_sortByDistance) {
                    shown.sort((a, b) => a.route.distanceMeters.compareTo(b.route.distanceMeters));
                  }
                  final top = scored.isEmpty ? null : scored.first;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (top != null) _MapCard(top: top),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(_listTitle(top?.best?.start),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: RwColors.tekst)),
                          ),
                          Text('${shown.length} ${shown.length == 1 ? 'route' : 'routes'}',
                              style: const TextStyle(fontSize: 13, color: RwColors.tekstZacht)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (shown.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('Geen routes met dit filter.',
                              textAlign: TextAlign.center, style: TextStyle(color: RwColors.tekstZacht)),
                        ),
                      for (final s in shown) ...[
                        _RouteCard(item: s),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _listTitle(DateTime? t) {
    if (t == null) return 'Jouw routes';
    final now = DateTime.now();
    final tomorrow = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays >= 1;
    if (tomorrow) return 'Voor morgen';
    if (t.hour < 12) return 'Voor vanochtend';
    if (t.hour < 17) return 'Voor vanmiddag';
    return 'Voor vanavond';
  }
}

/// Uitleg over de wind op een route, in één korte zin.
String windSummary(StartTimeScore? s) {
  final rw = s?.routeWind;
  final w = s?.weather;
  if (rw == null || w == null) return w == null ? 'Weer wordt geladen' : 'Wind ${Fmt.wind(w.windSpeed)}';
  if (rw.headwindAvg < 4) return 'Weinig tegenwind';
  if (rw.firstHalfHead - rw.secondHalfHead > 4) return 'Wind op de terugweg mee';
  if (rw.secondHalfHead - rw.firstHalfHead > 4) return 'Tegenwind op de terugweg';
  return 'Wind ${Fmt.wind(w.windSpeed)}, gelijk verdeeld';
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.item});
  final RouteScore item;

  @override
  Widget build(BuildContext context) {
    final r = item.route;
    final gain = r.elevationGainMeters ?? 0;
    final details = '${Fmt.km(r.distanceMeters, decimals: 1)} · ${gain < 15 ? 'vlak' : '${gain.round()} m hoogte'}';
    return RwPanel(
      padding: const EdgeInsets.all(12),
      onTap: () => context.go('/routes/${r.id}'),
      child: Row(
        children: [
          IconBox(
            icon: Icons.route,
            size: 64,
            iconSize: 28,
            background: RwColors.primairZacht,
            color: RwColors.primair,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (r.isFavorite)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.star, size: 16, color: RwColors.oranje),
                      ),
                    Expanded(
                      child: Text(r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: RwColors.tekst)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(details, style: const TextStyle(fontSize: 13, color: RwColors.tekstZacht)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.air, size: 14, color: RwColors.primair),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item.best == null ? windSummary(null) : '${windSummary(item.best)} · ${Fmt.time(item.best!.start)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: RwColors.primair),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (item.best != null) ScoreBlock(item.score),
        ],
      ),
    );
  }
}

/// Kaartje met de aanbevolen route op een gestileerde kaart.
class _MapCard extends StatelessWidget {
  const _MapCard({required this.top});
  final RouteScore top;

  @override
  Widget build(BuildContext context) {
    final best = top.best;
    return GestureDetector(
      onTap: () => context.go('/routes/${top.route.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RwRadius.r24),
        child: SizedBox(
          height: 200,
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _MapPainter(decodePolyline(top.route.polyline)))),
              Positioned(
                left: 12,
                top: 12,
                right: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _MapLabel(
                    icon: Icons.schedule,
                    text: best == null
                        ? top.route.name
                        : 'Aanbevolen om ${Fmt.time(best.start)} · ${top.route.name}',
                    bold: true,
                  ),
                ),
              ),
              const Positioned(left: 12, bottom: 12, child: _MapLabel(dot: true, text: 'Start')),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({this.icon, this.dot = false, required this.text, this.bold = false});
  final IconData? icon;
  final bool dot;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: RwColors.oppervlak, borderRadius: BorderRadius.circular(RwRadius.rond)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 14, color: RwColors.tekst),
          if (dot)
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: RwColors.primair, shape: BoxShape.circle),
            ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                color: bold ? RwColors.tekst : RwColors.tekstZacht,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gestileerde kaart (geen echte kaartdata): zachte vlakken, witte wegen en de route in oranje.
class _MapPainter extends CustomPainter {
  _MapPainter(this.points);
  final List<LatLng> points;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE6ECE8));
    final park = Paint()..color = RwColors.primairZacht;
    canvas.drawOval(Rect.fromLTWH(-size.width * 0.1, -size.height * 0.35, size.width * 0.75, size.height * 0.75), park);
    canvas.drawOval(Rect.fromLTWH(size.width * 0.62, size.height * 0.7, size.width * 0.5, size.height * 0.5), park);
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 6;
    canvas.drawLine(Offset(0, size.height * 0.6), Offset(size.width, size.height * 0.6), road);
    canvas.drawLine(Offset(size.width * 0.29, 0), Offset(size.width * 0.29, size.height), road);
    canvas.drawLine(Offset(size.width * 0.79, 0), Offset(size.width * 0.69, size.height), road);

    if (points.length < 2) return;
    var minLat = points.first.lat, maxLat = points.first.lat;
    var minLon = points.first.lon, maxLon = points.first.lon;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    final lonScale = math.cos(((minLat + maxLat) / 2) * math.pi / 180);
    final w = math.max((maxLon - minLon) * lonScale, 1e-9);
    final h = math.max(maxLat - minLat, 1e-9);
    const padX = 40.0, padTop = 52.0, padBottom = 44.0;
    final scale = math.min((size.width - 2 * padX) / w, (size.height - padTop - padBottom) / h);
    final ox = (size.width - w * scale) / 2;
    final oy = padTop + ((size.height - padTop - padBottom) - h * scale) / 2;
    Offset map(LatLng p) => Offset(ox + (p.lon - minLon) * lonScale * scale, oy + (maxLat - p.lat) * scale);

    final path = Path()..moveTo(map(points.first).dx, map(points.first).dy);
    for (final p in points.skip(1)) {
      final o = map(p);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = RwColors.oranje
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final start = map(points.first);
    canvas.drawCircle(start, 9, Paint()..color = Colors.white);
    canvas.drawCircle(start, 7, Paint()..color = RwColors.primair);
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.points != points;
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'year_story_screen.dart' show openYearStory;
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/best_efforts.dart';
import '../../domain/geo.dart';
import '../../domain/year_recap.dart';
import '../../shared/widgets.dart';
import '../routes/route_map.dart';
import '../../core/appearance.dart';

const _months = ['januari', 'februari', 'maart', 'april', 'mei', 'juni', 'juli', 'augustus', 'september', 'oktober', 'november', 'december'];
const _days = ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'];

void openHeatmap(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HeatmapScreen()));
void openCalendar(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RunCalendarScreen()));
void openYearRecap(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const YearRecapScreen()));

// ---------------------------------------------------------------------------
// Heatmap: al je runs op één kaart
// ---------------------------------------------------------------------------

class HeatmapScreen extends ConsumerStatefulWidget {
  const HeatmapScreen({super.key});

  @override
  ConsumerState<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends ConsumerState<HeatmapScreen> {
  int? _year;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final years = {for (final a in all) a.startedAt.toLocal().year}.toList()..sort((a, b) => b.compareTo(a));
    final runs = all.where((a) => a.hasTrack && (_year == null || a.startedAt.toLocal().year == _year)).toList();
    final lines = [
      for (final a in runs) [for (final p in decodePolyline(a.trackPolyline!)) ll.LatLng(p.lat, p.lon)],
    ].where((l) => l.length >= 2).toList();
    final allPts = [for (final l in lines) ...l];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mijn heatmap'),
        actions: [
          if (years.length > 1)
            PopupMenuButton<int?>(
              tooltip: 'Jaar',
              initialValue: _year,
              onSelected: (y) => setState(() => _year = y == 0 ? null : y),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 0, child: Text('Alle jaren')),
                for (final y in years) PopupMenuItem(value: y, child: Text('$y')),
              ],
              icon: const Icon(Icons.filter_alt_outlined),
            ),
        ],
      ),
      body: lines.isEmpty
          ? EmptyState(
              icon: Icons.map_outlined,
              title: 'Nog geen sporen',
              message: 'Runs met een GPS-spoor (opgenomen in Kadans, uit Strava of geïmporteerd) verschijnen hier samen op één kaart.',
            )
          : ValueListenableBuilder<MapLayer>(
              valueListenable: mapLayerNotifier,
              builder: (context, layer, _) {
                final photo = layer == MapLayer.satelliet;
                return Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(
                        initialCameraFit: CameraFit.coordinates(coordinates: allPts, padding: const EdgeInsets.all(40), maxZoom: 15),
                        backgroundColor: mapBackground,
                        minZoom: 5,
                        maxZoom: 18,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                      ),
                      children: [
                        baseTileLayer(photo),
                        PolylineLayer(polylines: [
                          for (final l in lines) Polyline(points: l, strokeWidth: 3, color: RwColors.accent.withValues(alpha: 0.35)),
                        ]),
                      ],
                    ),
                    Positioned(top: 10, left: 10, child: mapLayerToggle(layer)),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: RwColors.background.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
                        child: Text('${lines.length} runs${_year == null ? '' : ' in $_year'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    mapAttribution(photo),
                  ],
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kalender
// ---------------------------------------------------------------------------

class RunCalendarScreen extends ConsumerStatefulWidget {
  const RunCalendarScreen({super.key});

  @override
  ConsumerState<RunCalendarScreen> createState() => _RunCalendarScreenState();
}

class _RunCalendarScreenState extends ConsumerState<RunCalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _openDay(BuildContext context, List<Activity> runs) {
    if (runs.length == 1 && runs.first.id != null) {
      Navigator.of(context).pop();
      context.go('/runs/${runs.first.id}');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in runs)
              ListTile(
                leading: TileIcon(Icons.directions_run, color: RwColors.accent),
                title: Text('${Fmt.km(a.distanceMeters)} · ${Fmt.pace(a.paceSecondsPerKm)}'),
                subtitle: Text('${Fmt.time(a.startedAt)} · ${Fmt.duration(a.movingTimeSeconds)}'),
                onTap: a.id == null
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).pop();
                        context.go('/runs/${a.id}');
                      },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final byDay = <int, List<Activity>>{};
    for (final a in all) {
      final t = a.startedAt.toLocal();
      if (t.year == _month.year && t.month == _month.month) byDay.putIfAbsent(t.day, () => []).add(a);
    }
    final km = byDay.values.expand((l) => l).fold<double>(0, (s, a) => s + a.distanceMeters);
    final maxDay = byDay.values.map((l) => l.fold<double>(0, (s, a) => s + a.distanceMeters)).fold<double>(1, (a, b) => a > b ? a : b);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = DateTime(_month.year, _month.month, 1).weekday - 1;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Kalender')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Vorige maand',
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text('${_months[_month.month - 1]} ${_month.year}',
                    textAlign: TextAlign.center, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Volgende maand',
                onPressed: _month.year == now.year && _month.month == now.month
                    ? null
                    : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Text('${byDay.values.expand((l) => l).length} runs · ${Fmt.km(km, decimals: 1)} · ${byDay.length} dagen gelopen',
              textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted)),
          const SizedBox(height: 16),
          Row(children: [
            for (final d in ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'])
              Expanded(child: Text(d, textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 12))),
          ]),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (var i = 0; i < offset; i++) const SizedBox.shrink(),
              for (var d = 1; d <= daysInMonth; d++)
                () {
                  final runs = byDay[d];
                  final m = runs?.fold<double>(0, (s, a) => s + a.distanceMeters) ?? 0;
                  final isToday = _month.year == now.year && _month.month == now.month && d == now.day;
                  return Semantics(
                    button: runs != null,
                    label: '$d ${_months[_month.month - 1]}${runs == null ? '' : ', ${Fmt.km(m, decimals: 1)}'}',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: runs == null ? null : () => _openDay(context, runs),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: runs == null ? Colors.transparent : RwColors.accent.withValues(alpha: 0.25 + 0.75 * (m / maxDay)),
                          border: isToday ? Border.all(color: RwColors.text, width: 1.5) : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$d',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: runs == null ? FontWeight.w400 : FontWeight.w800,
                                  color: runs == null ? RwColors.subtle : RwColors.accentDark,
                                )),
                            if (runs != null)
                              Text((m / 1000).toStringAsFixed(m >= 10000 ? 0 : 1).replaceAll('.', ','),
                                  style: TextStyle(fontSize: 9, color: RwColors.accentDark)),
                          ],
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Jaaroverzicht
// ---------------------------------------------------------------------------

class YearRecapScreen extends ConsumerStatefulWidget {
  const YearRecapScreen({super.key});

  @override
  ConsumerState<YearRecapScreen> createState() => _YearRecapScreenState();
}

class _YearRecapScreenState extends ConsumerState<YearRecapScreen> {
  late int _year = DateTime.now().year;
  final _card = GlobalKey();
  bool _busy = false;

  Future<void> _share(YearRecap r) async {
    setState(() => _busy = true);
    try {
      final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('Afbeelding maken mislukt.');
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png', name: 'runwise-${r.year}.png')],
        text: 'Mijn ${r.year} in runs: ${r.km.round()} km 🏃',
      ));
    } catch (_) {
      if (mounted) showMessage(context, 'Delen is niet gelukt.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final years = {for (final a in all) a.startedAt.toLocal().year}.toList()..sort((a, b) => b.compareTo(a));
    final r = yearRecap(all, _year);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jaaroverzicht'),
        actions: [
          if (years.length > 1)
            PopupMenuButton<int>(
              initialValue: _year,
              onSelected: (y) => setState(() => _year = y),
              itemBuilder: (_) => [for (final y in years) PopupMenuItem(value: y, child: Text('$y'))],
              icon: const Icon(Icons.calendar_today_outlined),
            ),
        ],
      ),
      body: r == null
          ? EmptyState(icon: Icons.insights, title: 'Nog geen runs in $_year', message: 'Zodra je loopt, zie je hier je jaar.')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: FittedBox(
                    child: RepaintBoundary(key: _card, child: _RecapCard(r: r)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => openYearStory(context, year: _year),
                  icon: const Icon(Icons.auto_stories_outlined),
                  label: const Text('Bekijk als verhaal'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _share(r),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Deel je jaar'),
                ),
                const SizedBox(height: 16),
                RwCard(
                  title: 'MEER OVER JE JAAR',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _line(Icons.calendar_month, 'Drukste maand', '${_months[r.bestMonth - 1]} (${r.bestMonthKm.round()} km)'),
                      _line(Icons.today, 'Favoriete dag', _days[r.favouriteWeekday - 1]),
                      _line(Icons.wb_twilight, 'Liefst in de', r.favouritePartOfDay),
                      _line(Icons.local_fire_department, 'Langste reeks', '${r.longestStreakWeeks} weken op rij'),
                      if (r.longest != null)
                        _line(Icons.straighten, 'Langste run', '${Fmt.km(r.longest!.distanceMeters, decimals: 1)} (${Fmt.date(r.longest!.startedAt)})'),
                      for (final e in r.fastest.entries.where((e) => const [1000, 5000, 10000, 21098].contains(e.key)))
                        _line(Icons.emoji_events_outlined, 'Snelste ${bestEffortLabel(e.key)}', Fmt.duration(e.value)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _line(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 20, color: RwColors.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(color: RwColors.muted))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _RecapCard extends StatelessWidget {
  const _RecapCard({required this.r});
  final YearRecap r;

  @override
  Widget build(BuildContext context) {
    final maxM = r.perMonthKm.fold<double>(1, (a, b) => a > b ? a : b);
    Widget stat(String v, String l) => Expanded(
          child: Column(children: [
            Text(v, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 26, fontWeight: FontWeight.w800)),
            Text(l, style: TextStyle(color: RwColors.muted, fontSize: 11)),
          ]),
        );
    return Container(
      width: 360,
      height: 450,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      color: RwColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            kadansLockup(height: 18, mark: kadansImage('assets/logo/mark.png', height: 18)),
            const Spacer(),
            Text('${r.year}', style: TextStyle(color: RwColors.muted, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 18),
          Text('MIJN JAAR IN RUNS', style: TextStyle(color: RwColors.accent, fontWeight: FontWeight.w800, letterSpacing: 1)),
          Text(r.km.round().toString(),
              style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 84, fontWeight: FontWeight.w800, height: 1)),
          Text('kilometer', style: TextStyle(color: RwColors.muted, fontSize: 16)),
          const SizedBox(height: 18),
          Row(children: [
            stat('${r.runs}', 'runs'),
            stat('${(r.seconds / 3600).round()}', 'uur'),
            stat('${r.elevation.round()}', 'hoogtemeters'),
          ]),
          const Spacer(),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var m = 0; m < 12; m++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: 4 + 56 * (r.perMonthKm[m] / maxM),
                            decoration: BoxDecoration(
                              color: m == r.bestMonth - 1 ? RwColors.accent : RwColors.bar,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(_months[m].substring(0, 1).toUpperCase(), style: TextStyle(color: RwColors.subtle, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

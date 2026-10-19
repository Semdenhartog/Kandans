import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
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
import '../../domain/route_drawing.dart';
import '../../shared/widgets.dart';
import 'route_map.dart';

/// Zelf een route tekenen: tik punten op de kaart, de route volgt paden en wegen.
class DrawRouteScreen extends ConsumerStatefulWidget {
  const DrawRouteScreen({super.key});

  @override
  ConsumerState<DrawRouteScreen> createState() => _DrawRouteScreenState();
}

class _DrawRouteScreenState extends ConsumerState<DrawRouteScreen> {
  static const _maxTaps = 25;

  final _map = MapController();
  final _taps = <LatLng>[];
  DrawShape _shape = DrawShape.loop;
  GeneratedLoop? _routed;
  bool _busy = false;
  bool _saving = false;
  String? _error;
  Timer? _debounce;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  double _pace() {
    final runs = ref.read(activitiesProvider).value ?? const <Activity>[];
    final recent = runs.take(10).where((a) => a.paceSecondsPerKm > 0).toList();
    if (recent.isEmpty) return 360;
    return recent.fold<double>(0, (s, a) => s + a.paceSecondsPerKm) / recent.length;
  }

  void _changed() {
    setState(() {
      _error = null;
      if (_taps.length < 2) _routed = null;
    });
    _debounce?.cancel();
    if (_taps.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 600), _follow);
  }

  Future<void> _follow() async {
    final id = ++_request;
    setState(() => _busy = true);
    try {
      final loop = await ref.read(routeGeneratorProvider).followPath(drawWaypoints(_taps, _shape));
      if (!mounted || id != _request) return;
      setState(() => _routed = loop);
    } catch (e) {
      if (!mounted || id != _request) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && id == _request) setState(() => _busy = false);
    }
  }

  void _tap(LatLng p) {
    if (_taps.length >= _maxTaps) {
      showMessage(context, 'Maximaal $_maxTaps punten. Haal er een weg of sla de route op.');
      return;
    }
    _taps.add(p);
    _changed();
  }

  void _undo() {
    if (_taps.isEmpty) return;
    _taps.removeLast();
    _changed();
  }

  void _remove(int i) {
    _taps.removeAt(i);
    _changed();
  }

  Future<void> _clear() async {
    if (_taps.length > 2 && !await confirmDialog(context, title: 'Alles wissen?', message: 'Je getekende punten worden weggehaald.')) {
      return;
    }
    _taps.clear();
    _changed();
  }

  Future<void> _save() async {
    final loop = _routed;
    if (loop == null || loop.points.length < 2) return;
    final km = (loop.distanceMeters / 1000).toStringAsFixed(1).replaceAll('.', ',');
    final name = await _askName('Eigen route $km km');
    if (name == null) return;
    setState(() => _saving = true);
    try {
      final route = buildRoute(loop.points, name: name, source: 'drawn', estimatedPaceSecPerKm: _pace());
      final id = await ref.read(repositoryProvider).addRoute(route);
      ref.invalidate(routesProvider);
      final linked = await ref.read(syncServiceProvider).autoLinkRuns().catchError((_) => 0);
      if (!mounted) return;
      showMessage(
        context,
        linked > 0 ? 'Route opgeslagen. $linked eerdere ${linked == 1 ? 'run' : 'runs'} op deze route gekoppeld.' : 'Route opgeslagen.',
      );
      context.go('/routes/$id');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _askName(String suggestion) async {
    final c = TextEditingController(text: suggestion);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Route opslaan'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Naam'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Opslaan')),
        ],
      ),
    );
    c.dispose();
    final t = name?.trim();
    return t == null ? null : (t.isEmpty ? suggestion : t);
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(weatherLocationProvider).value;
    final center = loc == null ? const LatLng(52.15, 5.4) : LatLng(loc.latitude, loc.longitude);
    final loop = _routed;
    final meters = loop?.distanceMeters ?? straightLength(drawWaypoints(_taps, _shape));
    final exact = loop != null;
    final secs = meters / 1000 * _pace();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route tekenen'),
        actions: [
          IconButton(tooltip: 'Laatste punt weghalen', onPressed: _taps.isEmpty ? null : _undo, icon: const Icon(Icons.undo)),
          IconButton(tooltip: 'Alles wissen', onPressed: _taps.isEmpty ? null : _clear, icon: const Icon(Icons.delete_sweep_outlined)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (loc == null && ref.watch(weatherLocationProvider).isLoading)
                  const LoadingView()
                else
                  DrawRouteMap(
                    controller: _map,
                    center: center,
                    taps: _taps,
                    routed: loop?.points ?? const [],
                    onTap: _tap,
                    onMoveTap: _remove,
                  ),
                if (_taps.isEmpty)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: RwColors.background.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: RwColors.border),
                        ),
                        child: const Text(
                          'Tik je startpunt en daarna de plekken waar je langs wilt. De route volgt vanzelf paden en wegen. '
                          'Lang drukken op een punt haalt het weg.',
                          style: TextStyle(height: 1.4),
                        ),
                      ),
                    ),
                  ),
                if (_busy)
                  const Positioned(
                    top: 12,
                    left: 12,
                    child: Chip(
                      avatar: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      label: Text('Route volgen…'),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<DrawShape>(
                    showSelectedIcon: false,
                    segments: [
                      for (final s in DrawShape.values)
                        ButtonSegment(
                          value: s,
                          label: Text(switch (s) { DrawShape.open => 'A → B', DrawShape.loop => 'Rondje', DrawShape.outAndBack => 'Heen en terug' }),
                          tooltip: s.label,
                        ),
                    ],
                    selected: {_shape},
                    onSelectionChanged: (s) {
                      _shape = s.first;
                      _changed();
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: StatTile(label: exact ? 'Afstand' : 'Hemelsbreed', value: _taps.length < 2 ? '–' : '${exact ? '' : '≈ '}${Fmt.km(meters, decimals: 1)}')),
                      const SizedBox(width: 8),
                      Expanded(child: StatTile(label: 'Omhoog', value: loop == null ? '–' : '${loop.ascentMeters.round()} m')),
                      const SizedBox(width: 8),
                      Expanded(child: StatTile(label: 'Looptijd', value: _taps.length < 2 ? '–' : Fmt.duration(secs))),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: RwColors.danger)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: loop == null || _busy || _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Route opslaan'),
                  ),
                  const SizedBox(height: 6),
                  const Text('Routes © openrouteservice.org | kaartdata © OpenStreetMap-bijdragers',
                      textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 10)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/poi_service.dart';
import '../../domain/geo.dart';
import '../../domain/run_paths.dart';

/// Looppaden aan of uit, gedeeld door alle kaarten en onthouden op het toestel. Standaard aan.
final runPathsNotifier = _RunPathsNotifier();

class _RunPathsNotifier extends ValueNotifier<bool> {
  _RunPathsNotifier() : super(true) {
    SharedPreferences.getInstance().then((p) => value = p.getBool(_key) ?? true).catchError((Object _) => true);
  }
  static const _key = 'map_run_paths';

  void toggle() {
    value = !value;
    SharedPreferences.getInstance().then((p) => p.setBool(_key, value)).ignore();
  }
}

/// Alleen voor de schermtests: vaste paden in plaats van Overpass.
@visibleForTesting
List<RunPath>? debugRunPaths;

final _poi = PoiService();
final _cache = <String, Future<List<RunPath>>>{};

Future<List<RunPath>> _pathsFor(LatLng p) {
  final key = runPathCellKey(p);
  return _cache[key] ??= _poi.runPaths(p).catchError((Object _) {
    _cache.remove(key); // later opnieuw proberen
    return const <RunPath>[];
  });
}

bool get _inTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// Gouden looppaden over de kaart: voet- en fietspaden en onverharde paden uit OpenStreetMap.
/// Zet als laag in een FlutterMap, onder de route en je eigen spoor.
class RunPathsLayer extends StatefulWidget {
  const RunPathsLayer({super.key, required this.center});

  /// Punt waar omheen de paden worden opgehaald (vak van ±3 km plus rand).
  final LatLng? center;

  @override
  State<RunPathsLayer> createState() => _RunPathsLayerState();
}

class _RunPathsLayerState extends State<RunPathsLayer> {
  List<RunPath> _paths = const [];
  String? _cell;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RunPathsLayer old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    if (debugRunPaths != null) {
      _paths = debugRunPaths!;
      return;
    }
    final c = widget.center;
    if (c == null || _inTest) return;
    final key = runPathCellKey(c);
    if (key == _cell) return;
    _cell = key;
    _pathsFor(c).then((p) {
      if (mounted && _cell == key) setState(() => _paths = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: runPathsNotifier,
      builder: (context, on, _) {
        if (!on || _paths.isEmpty) return const SizedBox.shrink();
        final dark = RwColors.isDark;
        final gold = dark ? RwColors.accent : RwColors.accentDeep;
        List<ll.LatLng> pts(RunPath p) => [for (final x in p.points) ll.LatLng(x.lat, x.lon)];
        final glow = <Polyline>[];
        final core = <Polyline>[];
        for (final p in _paths) {
          final line = pts(p);
          final trail = p.kind == RunPathKind.trail;
          final cycle = p.kind == RunPathKind.cycle;
          // Gloed: breed en heel transparant, zoals een warmtekaart.
          glow.add(Polyline(points: line, strokeWidth: trail ? 7 : 6, color: gold.withValues(alpha: dark ? 0.16 : 0.12)));
          core.add(Polyline(
            points: line,
            strokeWidth: trail ? 1.8 : 1.4,
            color: (trail ? (dark ? RwColors.accentLight : gold) : gold).withValues(alpha: cycle ? 0.55 : 0.85),
          ));
        }
        return Stack(children: [
          PolylineLayer(polylines: glow),
          PolylineLayer(polylines: core),
        ]);
      },
    );
  }
}

/// Ronde kaartknop om de looppaden aan/uit te zetten.
class RunPathsButton extends StatelessWidget {
  const RunPathsButton({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: runPathsNotifier,
        builder: (context, on, _) => Tooltip(
          message: on ? tr('Looppaden verbergen') : tr('Looppaden tonen'),
          child: Material(
            color: on ? RwColors.accent : RwColors.background.withValues(alpha: 0.88),
            shape: CircleBorder(side: BorderSide(color: on ? RwColors.accent : RwColors.border)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: runPathsNotifier.toggle,
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Icon(Icons.alt_route, size: 20, color: on ? RwColors.accentDark : RwColors.text),
              ),
            ),
          ),
        ),
      );
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../domain/geo.dart';
import '../../domain/lighting.dart';
import '../../domain/poi.dart';
import '../../domain/poster_map.dart';
import '../../domain/route_geometry.dart';
import '../../domain/run_paths.dart';
import 'offline_cache.dart';

/// Zoekt watertappunten en toiletten langs een route in OpenStreetMap (Overpass, gratis).
class PoiService {
  PoiService([http.Client? client]) : _http = client ?? http.Client();
  final http.Client _http;

  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  /// Vaste korte sleutel voor de opslag (FNV-1a over de vraag).
  static String _key(String query) {
    var h = 0x811c9dc5;
    for (final c in query.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return 'poi_${h.toRadixString(16)}';
  }

  /// Lopende vragen per server: Overpass staat maar 2 vragen tegelijk toe per telefoon *per server*.
  /// Meer dan dat wacht in de rij op de server zelf (en duurt dan juist veel langer).
  final _busy = <String, int>{};
  final _waiting = <String, List<Completer<void>>>{};

  Future<void> _slot(String url) async {
    if ((_busy[url] ?? 0) < 2) {
      _busy[url] = (_busy[url] ?? 0) + 1;
      return;
    }
    final c = Completer<void>();
    (_waiting[url] ??= []).add(c);
    await c.future;
  }

  void _release(String url) {
    final q = _waiting[url];
    if (q != null && q.isNotEmpty) {
      q.removeAt(0).complete(); // de plek gaat direct door naar de volgende
    } else {
      _busy[url] = ((_busy[url] ?? 1) - 1).clamp(0, 2);
    }
  }

  Future<String> _ask(String url, String query) async {
    await _slot(url);
    try {
      final res = await _http
          .post(Uri.parse(url), headers: {'User-Agent': 'Kadans/1.0 (nl.runwise.app)'}, body: {'data': query})
          .timeout(const Duration(seconds: 18));
      if (res.statusCode != 200) throw Exception('Overpass ${res.statusCode}');
      // Controleer dat het echt JSON is (bij drukte stuurt Overpass soms een HTML-pagina).
      parseOverpass(res.body);
      return res.body;
    } finally {
      _release(url);
    }
  }

  /// Dezelfde vraag die al onderweg is (bijv. scherm twee keer geopend) niet opnieuw stellen.
  final _inFlight = <String, Future<String>>{};

  /// Straatverlichting langs een route (verlicht, onverlicht, onbekend in meters). Een maand bewaard.
  Future<({double lit, double unlit, double unknown})> lighting(String polyline) async {
    final track = RouteTrack(decodePolyline(polyline));
    if (!track.isValid) return (lit: 0.0, unlit: 0.0, unknown: 0.0);
    final query = litQuery(sampleTrack(track));
    final key = _key(query);
    final cached = await OfflineCache.load(key, maxAge: const Duration(days: 30));
    if (cached?.data is String) {
      try {
        return lightingAlong(track, parseLitWays(cached!.data! as String));
      } catch (_) {}
    }
    try {
      final body = await _race(query);
      OfflineCache.save(key, body).ignore();
      return lightingAlong(track, parseLitWays(body));
    } catch (e) {
      final old = await OfflineCache.load(key);
      if (old?.data is String) return lightingAlong(track, parseLitWays(old!.data! as String));
      rethrow;
    }
  }

  /// Twee verschillende servers tegelijk (elk heeft zijn eigen limiet, dus dat kost niets), de derde
  /// erbij als die na 3 s nog niets hebben gezegd of als er een faalt. De snelste wint.
  Future<String> _race(String query) => _inFlight[query] ??= _raceNow(query).whenComplete(() => _inFlight.remove(query));

  Future<String> _raceNow(String query) {
    final done = Completer<String>();
    var started = 0, failed = 0;
    Object? lastError;
    Timer? next;
    void start() {
      if (done.isCompleted || started >= _endpoints.length) return;
      final url = _endpoints[started++];
      _ask(url, query).then((body) {
        if (!done.isCompleted) {
          next?.cancel();
          done.complete(body);
        }
      }, onError: (Object e) {
        lastError = e;
        failed++;
        if (failed == _endpoints.length && !done.isCompleted) {
          next?.cancel();
          done.completeError(Exception('Gegevens langs de route konden niet worden geladen. ($lastError)'));
        } else {
          start(); // deze faalde: meteen de volgende proberen
        }
      });
    }

    start();
    start();
    next = Timer(const Duration(seconds: 3), start);
    return done.future;
  }

  /// Straten, water en spoor rond een route, voor de kaart onder een poster. Twee maanden bewaard.
  Future<List<MapLine>> posterMap(String polyline) async {
    final pts = decodePolyline(polyline);
    if (pts.length < 2) return const [];
    final query = posterMapQuery(pts);
    final key = 'map_${_key(query)}';
    final cached = await OfflineCache.load(key, maxAge: const Duration(days: 60));
    if (cached?.data is String) {
      try {
        return decodePosterMap(cached!.data! as String);
      } catch (_) {}
    }
    final lines = parsePosterMap(await _race(query));
    OfflineCache.save(key, encodePosterMap(lines)).ignore();
    return lines;
  }

  /// Looppaden (voet-, fiets- en onverharde paden) rond een punt, per vak van ±3 km. Een maand bewaard.
  Future<List<RunPath>> runPaths(LatLng p) async {
    final key = runPathCellKey(p);
    final cached = await OfflineCache.load(key, maxAge: const Duration(days: 30));
    if (cached?.data is String) {
      try {
        return decodeRunPaths(cached!.data! as String);
      } catch (_) {}
    }
    try {
      final paths = parseRunPaths(await _race(runPathsQuery(p)));
      OfflineCache.save(key, encodeRunPaths(paths)).ignore();
      return paths;
    } catch (e) {
      final old = await OfflineCache.load(key);
      if (old?.data is String) return decodeRunPaths(old!.data! as String);
      rethrow;
    }
  }

  Future<List<RoutePoi>> alongRoute(String polyline) async {
    final track = RouteTrack(decodePolyline(polyline));
    if (!track.isValid) return const [];
    final query = overpassQuery(track.points);
    final key = _key(query);
    // Water en toiletten veranderen zelden: twee weken bewaren.
    final cached = await OfflineCache.load(key, maxAge: const Duration(days: 14));
    if (cached?.data is String) {
      try {
        return poisAlongRoute(parseOverpass(cached!.data! as String), track);
      } catch (_) {}
    }
    try {
      final body = await _race(query);
      OfflineCache.save(key, body).ignore();
      return poisAlongRoute(parseOverpass(body), track);
    } catch (e) {
      // Geen verbinding: dan maar een oudere versie, als die er is.
      final old = await OfflineCache.load(key);
      if (old?.data is String) return poisAlongRoute(parseOverpass(old!.data! as String), track);
      rethrow;
    }
  }
}

final poiServiceProvider = Provider<PoiService>((ref) => PoiService());

/// Voorzieningen per route (op polyline), onthouden zolang de app open is.
final routePoisProvider = FutureProvider.family<List<RoutePoi>, String>((ref, polyline) {
  return ref.watch(poiServiceProvider).alongRoute(polyline);
});

/// Achtergrondkaart voor een routeposter (op polyline).
final posterMapProvider = FutureProvider.family<List<MapLine>, String>((ref, polyline) {
  return ref.watch(poiServiceProvider).posterMap(polyline);
});

/// Verlichting per route (op polyline).
final routeLightingProvider = FutureProvider.family<({double lit, double unlit, double unknown}), String>((ref, polyline) {
  return ref.watch(poiServiceProvider).lighting(polyline);
});

/// Looppaden per vak (sleutel = vak), onthouden zolang de app open is.
final runPathsProvider = FutureProvider.family<List<RunPath>, String>((ref, cellKey) {
  final parts = cellKey.split('_');
  // Midden van het vak, zodat de vraag precies dit vak dekt.
  final p = LatLng(double.parse(parts[1]) + runPathCell / 2, double.parse(parts[2]) + runPathCell / 2);
  return ref.watch(poiServiceProvider).runPaths(p);
});

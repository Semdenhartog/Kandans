import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../domain/geo.dart';
import '../../domain/lighting.dart';
import '../../domain/poi.dart';
import '../../domain/route_geometry.dart';
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

  Future<String> _ask(String url, String query) async {
    final res = await _http
        .post(Uri.parse(url), headers: {'User-Agent': 'RunWise/1.0 (nl.runwise.app)'}, body: {'data': query})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Overpass ${res.statusCode}');
    // Controleer dat het echt JSON is (bij drukte stuurt Overpass soms een HTML-pagina).
    parseOverpass(res.body);
    return res.body;
  }

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
    final body = await _race(query);
    OfflineCache.save(key, body).ignore();
    return lightingAlong(track, parseLitWays(body));
  }

  /// Vraagt alle servers tegelijk; het eerste goede antwoord telt.
  Future<String> _race(String query) {
    final done = Completer<String>();
    var failed = 0;
    Object? lastError;
    for (final url in _endpoints) {
      _ask(url, query).then((body) {
        if (!done.isCompleted) done.complete(body);
      }, onError: (Object e) {
        lastError = e;
        if (++failed == _endpoints.length && !done.isCompleted) {
          done.completeError(Exception('Voorzieningen langs de route konden niet worden geladen. ($lastError)'));
        }
      });
    }
    return done.future;
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

/// Verlichting per route (op polyline).
final routeLightingProvider = FutureProvider.family<({double lit, double unlit, double unknown}), String>((ref, polyline) {
  return ref.watch(poiServiceProvider).lighting(polyline);
});

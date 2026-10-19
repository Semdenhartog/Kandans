import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../domain/geo.dart';
import '../../domain/poi.dart';
import '../../domain/route_geometry.dart';

/// Zoekt watertappunten en toiletten langs een route in OpenStreetMap (Overpass, gratis).
class PoiService {
  PoiService([http.Client? client]) : _http = client ?? http.Client();
  final http.Client _http;

  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  Future<List<RoutePoi>> alongRoute(String polyline) async {
    final track = RouteTrack(decodePolyline(polyline));
    if (!track.isValid) return const [];
    final query = overpassQuery(track.points);
    Object? lastError;
    for (final url in _endpoints) {
      try {
        final res = await _http
            .post(
              Uri.parse(url),
              headers: {'User-Agent': 'RunWise/1.0 (nl.runwise.app)'},
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 25));
        if (res.statusCode != 200) {
          lastError = Exception('Overpass ${res.statusCode}');
          continue;
        }
        return poisAlongRoute(parseOverpass(res.body), track);
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Voorzieningen langs de route konden niet worden geladen. ($lastError)');
  }
}

final poiServiceProvider = Provider<PoiService>((ref) => PoiService());

/// Voorzieningen per route (op polyline), onthouden zolang de app open is.
final routePoisProvider = FutureProvider.family<List<RoutePoi>, String>((ref, polyline) {
  return ref.watch(poiServiceProvider).alongRoute(polyline);
});

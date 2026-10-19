import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import '../../domain/geo.dart';
import '../../domain/route_geometry.dart';
import '../../domain/route_photos.dart';

class RoutePhotos {
  const RoutePhotos({this.photos = const [], this.streetConfigured = true, this.streetFailed = false});
  final List<RoutePhoto> photos;

  /// False als de Mapillary-sleutel nog niet op de server staat.
  final bool streetConfigured;
  final bool streetFailed;

  bool get hasStreet => photos.any((p) => p.source == PhotoSource.street);
}

/// Foto's langs een route: straatfoto's via onze server (Mapillary) en bezienswaardigheden via Wikipedia.
class RoutePhotosService {
  RoutePhotosService(this._db, [http.Client? client]) : _http = client ?? http.Client();
  final SupabaseClient _db;
  final http.Client _http;

  Future<({List<RoutePhoto> photos, bool configured})> street(RouteTrack t, {int max = 16}) async {
    final samples = photoSamples(t, max: max);
    if (samples.isEmpty) return (photos: const <RoutePhoto>[], configured: true);
    try {
      final res = await _db.functions.invoke('street-photos', body: {
        'points': [
          for (final s in samples) [s.point.lat, s.point.lon, s.bearing.roundToDouble()],
        ],
      });
      return (photos: parseStreetPhotos(res.data, samples), configured: true);
    } on FunctionException catch (e) {
      final code = e.details is Map ? (e.details as Map)['code'] : null;
      if (e.status == 503 && (code == 'not_configured' || code == 'bad_token')) {
        return (photos: const <RoutePhoto>[], configured: false);
      }
      rethrow;
    }
  }

  Future<List<RoutePhoto>> landmarks(RouteTrack t) async {
    final b = routeBounds(t.points);
    final uri = Uri.https('nl.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'formatversion': '2',
      'generator': 'geosearch',
      'ggsbbox': '${b.north}|${b.west}|${b.south}|${b.east}',
      'ggslimit': '50',
      'prop': 'pageimages|coordinates|description',
      'piprop': 'thumbnail',
      'pithumbsize': '640',
      'pilicense': 'free',
      'origin': '*',
    });
    final res = await _http.get(uri, headers: {'User-Agent': 'RunWise/1.0 (nl.runwise.app)'}).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return const [];
    return parseWikipediaLandmarks(res.body, t);
  }

  Future<RoutePhotos> forRoute(String polyline) async {
    final t = RouteTrack(decodePolyline(polyline));
    if (!t.isValid) return const RoutePhotos();
    final streetF = street(t).then<({List<RoutePhoto> photos, bool configured, bool failed})>(
      (r) => (photos: r.photos, configured: r.configured, failed: false),
      onError: (_) => (photos: const <RoutePhoto>[], configured: true, failed: true),
    );
    final landF = landmarks(t).catchError((_) => const <RoutePhoto>[]);
    final s = await streetF;
    final l = await landF;
    return RoutePhotos(photos: mergeRoutePhotos(s.photos, l), streetConfigured: s.configured, streetFailed: s.failed);
  }

  /// Eén omslagfoto voor de routelijst (een paar punten, snel).
  Future<RoutePhoto?> cover(String polyline) async {
    final t = RouteTrack(decodePolyline(polyline));
    if (!t.isValid) return null;
    try {
      final r = await street(t, max: 3);
      if (r.photos.isEmpty) return null;
      // Liefst het midden van de route.
      final mid = t.length / 2;
      return (r.photos.toList()..sort((a, b) => (a.meters - mid).abs().compareTo((b.meters - mid).abs()))).first;
    } catch (_) {
      return null;
    }
  }
}

final routePhotosServiceProvider = Provider<RoutePhotosService>((ref) => RoutePhotosService(ref.watch(supabaseProvider)));

/// Foto's per route (op polyline), onthouden zolang de app open is.
final routePhotosProvider = FutureProvider.family<RoutePhotos, String>((ref, polyline) {
  return ref.watch(routePhotosServiceProvider).forRoute(polyline);
});

final routeCoverProvider = FutureProvider.family<RoutePhoto?, String>((ref, polyline) {
  return ref.watch(routePhotosServiceProvider).cover(polyline);
});

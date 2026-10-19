import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import '../../domain/geo.dart';

/// Een gevonden adres of plaats.
class Place {
  const Place(this.label, this.lat, this.lon);
  final String label;
  final double lat;
  final double lon;
}

/// Een voorgesteld rondje van de server.
class GeneratedLoop {
  const GeneratedLoop({required this.points, required this.distanceMeters, required this.ascentMeters});
  final List<LatLng> points;
  final double distanceMeters;
  final double ascentMeters;
}

class RouteGeneratorService {
  RouteGeneratorService(this._db, [http.Client? client]) : _http = client ?? http.Client();
  final SupabaseClient _db;
  final http.Client _http;

  /// Zoekt Nederlandse adressen en plaatsen (PDOK Locatieserver, gratis).
  Future<List<Place>> searchAddress(String query) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    final uri = Uri.https('api.pdok.nl', '/bzk/locatieserver/search/v3_1/free', {
      'q': q,
      'rows': '6',
      'fl': 'weergavenaam,centroide_ll,type',
      'fq': 'type:(adres OR weg OR woonplaats OR postcode)',
    });
    final res = await _http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Adres zoeken is even niet gelukt.');
    return parsePdok(res.body);
  }

  /// Zet het PDOK-antwoord om. Publiek voor tests.
  static List<Place> parsePdok(String body) {
    final docs = ((jsonDecode(body) as Map)['response']?['docs'] as List?) ?? const [];
    final out = <Place>[];
    final point = RegExp(r'POINT\(([-\d.]+) ([-\d.]+)\)');
    for (final d in docs.cast<Map>()) {
      final m = point.firstMatch((d['centroide_ll'] ?? '') as String);
      if (m == null) continue;
      out.add(Place(d['weergavenaam'] as String? ?? 'Onbekend', double.parse(m.group(2)!), double.parse(m.group(1)!)));
    }
    return out;
  }

  /// Vraagt een paar rondjes van ongeveer [distanceMeters] aan vanaf het startpunt.
  Future<List<GeneratedLoop>> generate(double lat, double lon, double distanceMeters) async {
    try {
      final res = await _db.functions.invoke('route-generator', body: {
        'lat': lat,
        'lon': lon,
        'distance_m': distanceMeters.round(),
        'count': 4,
      });
      final routes = ((res.data as Map)['routes'] as List).cast<Map>();
      return [
        for (final r in routes)
          GeneratedLoop(
            points: [
              for (final c in (r['coordinates'] as List).cast<List>())
                LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble(), c.length > 2 ? (c[2] as num).toDouble() : null),
            ],
            distanceMeters: (r['distance_m'] as num).toDouble(),
            ascentMeters: (r['ascent_m'] as num).toDouble(),
          ),
      ];
    } on FunctionException catch (e) {
      final details = e.details is Map ? (e.details as Map).cast<String, dynamic>() : <String, dynamic>{};
      throw Exception(details['error'] ?? 'Routes maken is niet gelukt. Probeer het later opnieuw.');
    }
  }
}

final routeGeneratorProvider = Provider<RouteGeneratorService>(
  (ref) => RouteGeneratorService(ref.watch(supabaseProvider)),
);

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/barometer.dart';
import '../../domain/geo.dart';
import '../../domain/run_streams.dart';
import '../../domain/zones.dart';

/// Corrigeert de hoogte van een run met de hoogtekaart van Open-Meteo (gratis, zonder sleutel).
/// GPS-hoogte op een telefoon schommelt vaak 10 m of meer; dit maakt hoogtemeters veel betrouwbaarder.
class ElevationService {
  ElevationService([http.Client? client]) : _http = client ?? http.Client();
  final http.Client _http;

  Future<List<double>> _lookup(List<LatLng> pts) async {
    final out = <double>[];
    for (var i = 0; i < pts.length; i += 100) {
      final chunk = pts.sublist(i, i + 100 > pts.length ? pts.length : i + 100);
      final uri = Uri.https('api.open-meteo.com', '/v1/elevation', {
        'latitude': chunk.map((p) => p.lat.toStringAsFixed(5)).join(','),
        'longitude': chunk.map((p) => p.lon.toStringAsFixed(5)).join(','),
      });
      final res = await _http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception('Hoogte ophalen mislukt (${res.statusCode}).');
      final list = (jsonDecode(res.body) as Map)['elevation'] as List;
      out.addAll(list.map((e) => (e as num).toDouble()));
    }
    return out;
  }

  /// Geeft het verloop met verbeterde hoogte en de hoogtemeters terug (of null als het niet kan).
  Future<({Map<String, dynamic> streams, double gain})?> correct(Map<String, dynamic> streams) async {
    final s = RunStreams.fromJson(streams);
    final pos = s?.positions;
    if (s == null || pos == null || pos.length < 3) return null;
    final idx = elevationSampleIndices(s.distance);
    final ele = await _lookup(pointsAt(pos, idx));
    if (ele.length != idx.length) return null;
    final alt = interpolateElevation(s.distance, idx, ele);
    // Gemeten met de barometer? Dan zijn die hoogtemeters nauwkeuriger dan de hoogtekaart
    // (die mist bruggen, dijken en viaducten). De kaart gebruiken we dan alleen voor de grafiek.
    final baro = baroSeries(streams);
    final gain = baro != null ? barometricGain(baro) : elevationGain(alt);
    return (streams: {...streams, 'alt': alt, 'alt_src': 'dem'}, gain: gain);
  }
}

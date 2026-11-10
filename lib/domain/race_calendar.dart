// Wedstrijden uit officiële bekendmakingen van gemeenten (tabel race_calendar, gevuld door de functie
// race-import uit open overheidsdata, CC-0). Puur model + filters, zonder Flutter.

import 'dart:math' as math;

enum RaceKind { marathon, halve, trail, cross, loop, estafette }

enum RaceStatus { aangevraagd, melding, verleend }

class RaceListing {
  const RaceListing({
    required this.key,
    required this.name,
    required this.date,
    required this.kind,
    required this.status,
    required this.sourceUrl,
    this.municipality,
    this.place,
    this.lat,
    this.lon,
  });

  final String key;
  final String name;
  final DateTime date;
  final RaceKind kind;
  final RaceStatus status;
  final String sourceUrl;
  final String? municipality;
  final String? place;
  final double? lat, lon;

  /// Plaats zoals we die tonen: plaats uit de titel, anders de gemeente.
  String get where => (place?.trim().isNotEmpty ?? false) ? place!.trim() : (municipality ?? '');

  /// Gebruikelijke afstand bij deze soort (voor "Zet in Mijn wedstrijden"), in meters.
  double get typicalMeters => switch (kind) {
        RaceKind.marathon => 42195,
        RaceKind.halve => 21097.5,
        _ => 10000,
      };

  static RaceListing? fromRow(Map<String, dynamic> r) {
    final d = DateTime.tryParse('${r['race_date']}');
    final name = '${r['name'] ?? ''}'.trim();
    if (d == null || name.isEmpty) return null;
    T pick<T extends Enum>(List<T> values, Object? v, T fallback) =>
        values.firstWhere((x) => x.name == v, orElse: () => fallback);
    return RaceListing(
      key: '${r['key']}',
      name: name,
      date: DateTime(d.year, d.month, d.day),
      kind: pick(RaceKind.values, r['kind'], RaceKind.loop),
      status: pick(RaceStatus.values, r['status'], RaceStatus.aangevraagd),
      sourceUrl: '${r['source_url'] ?? ''}',
      municipality: r['municipality'] as String?,
      place: r['place'] as String?,
      lat: (r['lat'] as num?)?.toDouble(),
      lon: (r['lon'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toRow() => {
        'key': key,
        'name': name,
        'race_date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'kind': kind.name,
        'status': status.name,
        'source_url': sourceUrl,
        'municipality': municipality,
        'place': place,
        'lat': lat,
        'lon': lon,
      };

  /// Hemelsbreed afstand in km tot (lat, lon), of null als de plek onbekend is.
  double? kmFrom(double? fromLat, double? fromLon) {
    if (lat == null || lon == null || fromLat == null || fromLon == null) return null;
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat! - fromLat), dLon = rad(lon! - fromLon);
    final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(fromLat)) * math.cos(rad(lat!)) * math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(a.toDouble()));
  }
}

/// Komende wedstrijden binnen [maxKm] (null = heel Nederland), eventueel één soort, op datum.
/// Wedstrijden zonder plek tellen alleen mee bij "heel Nederland".
List<RaceListing> racesNear(
  List<RaceListing> all, {
  double? lat,
  double? lon,
  double? maxKm,
  Set<RaceKind>? kinds,
  DateTime? today,
}) {
  final t = today ?? DateTime.now();
  final from = DateTime(t.year, t.month, t.day);
  return [
    for (final r in all)
      if (!r.date.isBefore(from) &&
          (kinds == null || kinds.isEmpty || kinds.contains(r.kind)) &&
          (maxKm == null || ((r.kmFrom(lat, lon) ?? double.infinity) <= maxKm)))
        r,
  ]..sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : (a.kmFrom(lat, lon) ?? 1e9).compareTo(b.kmFrom(lat, lon) ?? 1e9);
    });
}

/// PDOK-luchtfototegels (EPSG:3857) rond een punt: tegelnummer + positie binnen de tegel (0..1).
({int x, int y, double fx, double fy}) webMercatorTile(double lat, double lon, int zoom) {
  final n = math.pow(2, zoom).toDouble();
  final x = (lon + 180) / 360 * n;
  final latRad = lat * math.pi / 180;
  final y = (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n;
  return (x: x.floor(), y: y.floor(), fx: x - x.floor(), fy: y - y.floor());
}

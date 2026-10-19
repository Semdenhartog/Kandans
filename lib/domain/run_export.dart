import '../data/models/models.dart';
import 'geo.dart';

String _csv(Object? v) {
  final s = v?.toString() ?? '';
  if (s.contains(RegExp('[",;\n]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String _n(num? v, [int d = 1]) => v == null ? '' : v.toStringAsFixed(d);

String _pace(double s) {
  if (s <= 0) return '';
  final t = s.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

/// Al je runs als CSV (opent in Excel, Numbers en Google Spreadsheets). Puntkomma als scheiding
/// en punt als decimaalteken, zodat het in zowel Nederlandse als Engelse Excel goed leest.
String runsCsv(List<Activity> runs, {Map<String, String> shoeNames = const {}, Map<String, String> routeNames = const {}}) {
  const feel = {1: 'zwaar', 2: 'oke', 3: 'top'};
  final b = StringBuffer('sep=;\n')
    ..writeln([
      'datum', 'starttijd', 'afstand_km', 'tijd_s', 'tempo_min_per_km', 'bron', 'route', 'schoen',
      'temperatuur_c', 'gevoelstemperatuur_c', 'wind_kmh', 'windrichting_graden', 'luchtvochtigheid_pct',
      'hartslag_gem', 'hoogtemeters', 'gevoel', 'notitie',
    ].join(';'));
  final sorted = [...runs]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  for (final a in sorted) {
    final t = a.startedAt.toLocal();
    b.writeln([
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}',
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
      _n(a.distanceMeters / 1000, 2),
      a.movingTimeSeconds,
      _pace(a.paceSecondsPerKm),
      a.source,
      _csv(routeNames[a.routeId] ?? ''),
      _csv(shoeNames[a.shoeId] ?? ''),
      _n(a.temperatureCelsius),
      _n(a.feelsLikeCelsius),
      _n(a.windSpeedKmh),
      _n(a.windDirectionDegrees, 0),
      _n(a.humidityPct, 0),
      a.averageHeartRate ?? '',
      _n(a.elevationGainMeters, 0),
      feel[a.feel] ?? '',
      _csv(a.note ?? ''),
    ].join(';'));
  }
  return b.toString();
}

String _xml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Alle runs met een GPS-spoor in één GPX-bestand (één track per run).
String runsGpx(List<Activity> runs) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="RunWise" xmlns="http://www.topografix.com/GPX/1/1">');
  final sorted = [...runs.where((a) => a.hasTrack)]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  for (final a in sorted) {
    final pts = decodePolyline(a.trackPolyline!);
    if (pts.length < 2) continue;
    final km = (a.distanceMeters / 1000).toStringAsFixed(1);
    b
      ..writeln('  <trk>')
      ..writeln('    <name>${_xml('Run ${a.startedAt.toLocal().toIso8601String().substring(0, 16)} · $km km')}</name>')
      ..writeln('    <type>running</type>')
      ..writeln('    <trkseg>');
    // Tijden schatten we gelijkmatig over de run (het spoor heeft geen tijd per punt).
    final total = a.movingTimeSeconds;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      final t = a.startedAt.toUtc().add(Duration(seconds: (total * i / (pts.length - 1)).round()));
      b.writeln('      <trkpt lat="${p.lat.toStringAsFixed(6)}" lon="${p.lon.toStringAsFixed(6)}"><time>${t.toIso8601String().split('.').first}Z</time></trkpt>');
    }
    b
      ..writeln('    </trkseg>')
      ..writeln('  </trk>');
  }
  b.writeln('</gpx>');
  return b.toString();
}

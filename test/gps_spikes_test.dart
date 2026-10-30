import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/gps_spikes.dart';

/// Run naar het oosten, 3 m/s, één punt per seconde. [offsets]: punt → meters extra naar het noorden.
Map<String, dynamic> _run(int seconds, {Map<int, double> offsets = const {}}) {
  final ll = <List<double>>[];
  final t = <double>[];
  final d = <double>[];
  LatLng? prev;
  var dist = 0.0;
  for (var s = 0; s <= seconds; s++) {
    final p = LatLng(52.0 + (offsets[s] ?? 0) / 111320, 5.0 + s * 3.0 / 68540);
    if (prev != null) dist += distanceMeters(prev, p);
    prev = p;
    t.add(s.toDouble());
    d.add(dist);
    ll.add([p.lat, p.lon]);
  }
  return {'t': t, 'd': d, 'll': ll};
}

void main() {
  test('schone run: geen sprongen', () {
    expect(findGpsSpikes(_run(600)), isEmpty);
  });

  test('één punt 200 m ernaast: gevonden, hersteld tot de echte afstand', () {
    final clean = _run(600);
    final spiky = _run(600, offsets: {300: 200});
    final realKm = (clean['d'] as List).last as double;
    final spikes = findGpsSpikes(spiky);
    expect(spikes, hasLength(1));
    expect(spikes.first.from, 299);
    expect(spikes.first.to, 301);
    expect(spikes.first.extraMeters, closeTo(400 - 6, 5));
    expect(spikes.first.atMeters, closeTo(897, 3));
    expect(spikes.first.peakKmh, greaterThan(100));

    final fixed = removeGpsSpikes(spiky, spikes)!;
    expect(fixed.distanceMeters, closeTo(realKm, 1));
    expect(fixed.movingSeconds, 600);
    // Het foute punt ligt weer op de lijn.
    final p = (fixed.streams['ll'] as List)[300] as List;
    expect((p[0] as num).toDouble(), closeTo(52.0, 1e-5));
    // Afstand loopt nergens terug.
    final d = (fixed.streams['d'] as List).cast<double>();
    for (var i = 1; i < d.length; i++) {
      expect(d[i], greaterThanOrEqualTo(d[i - 1]), reason: 'punt $i');
    }
  });

  test('twee sprongen, alleen de eerste herstellen', () {
    final spiky = _run(900, offsets: {200: 150, 700: 300});
    final spikes = findGpsSpikes(spiky);
    expect(spikes, hasLength(2));
    final before = (spiky['d'] as List).last as double;
    final fixed = removeGpsSpikes(spiky, [spikes.first])!;
    expect(fixed.distanceMeters, closeTo(before - spikes.first.extraMeters, 1));
  });

  test('kleine GPS-ruis telt niet', () {
    expect(findGpsSpikes(_run(600, offsets: {100: 4, 101: -3, 400: 5})), isEmpty);
  });

  test('snelle loper (interval 6 m/s) is geen sprong', () {
    final t = [for (var s = 0; s <= 300; s++) s.toDouble()];
    final d = [for (var s = 0; s <= 300; s++) s * (s > 100 && s < 160 ? 6.0 : 3.5)];
    // cumulatief maken
    for (var i = 1; i < d.length; i++) {
      d[i] = d[i - 1] + (i > 100 && i < 160 ? 6.0 : 3.5);
    }
    expect(findGpsSpikes({'t': t, 'd': d}), isEmpty);
  });
}

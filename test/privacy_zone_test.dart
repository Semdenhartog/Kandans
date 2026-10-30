import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/privacy_zone.dart';

/// Rechte lijn naar het noorden: elk punt ~111 m verder (0,001 graad).
List<LatLng> _line(int n, {double lat = 52.15, double lon = 5.58}) => [for (var i = 0; i < n; i++) LatLng(lat + i * 0.001, lon)];

void main() {
  test('knipt begin en eind weg en houdt het midden', () {
    final pts = _line(41); // ~4,4 km
    final kept = privacyTrimmedPoints(pts, meters: 500);
    expect(kept, isNotEmpty);
    for (final p in kept) {
      expect(distanceMeters(p, pts.first), greaterThan(500));
      expect(distanceMeters(p, pts.last), greaterThan(500));
    }
    // Ongeveer 4 punten aan elke kant weg.
    expect(kept.length, inInclusiveRange(30, 33));
  });

  test('rondje dat thuis begint en eindigt: ook het stuk langs huis halverwege verdwijnt', () {
    final home = const LatLng(52.15, 5.58);
    final out = _line(20);
    final back = out.reversed.toList();
    // Heen en terug langs huis, dan nog een stuk de andere kant op en terug.
    final south = [for (var i = 1; i < 15; i++) LatLng(52.15 - i * 0.001, 5.58)];
    final pts = [...out, ...back.skip(1), ...south, ...south.reversed.skip(1), home];
    final kept = privacyTrimmedPoints(pts, meters: 500);
    expect(kept.every((p) => distanceMeters(p, home) > 500), isTrue);
  });

  test('korte run rond huis: geen kaart', () {
    expect(privacyTrimmedPolyline(encodePolyline(_line(9)), meters: 500), isNull); // ~900 m heen
    expect(privacyTrimmedPolyline(null), isNull);
    expect(privacyTrimmedPolyline(''), isNull);
  });

  test('lange route wordt vereenvoudigd en blijft geldig', () {
    final pts = [for (var i = 0; i < 3000; i++) LatLng(52.15 + i * 0.0001, 5.58)];
    final enc = privacyTrimmedPolyline(encodePolyline(pts), meters: 200, maxPoints: 400)!;
    final back = decodePolyline(enc);
    expect(back.length, lessThanOrEqualTo(401));
    expect(distanceMeters(back.first, pts.first), greaterThan(195));
    expect(distanceMeters(back.last, pts.last), greaterThan(195));
  });
}

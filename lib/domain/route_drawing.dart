import 'geo.dart';

enum DrawShape {
  open('Van A naar B'),
  loop('Rondje terug naar start'),
  outAndBack('Heen en terug');

  const DrawShape(this.label);
  final String label;
}

/// De punten die naar de routeplanner gaan, op basis van wat je tikte.
List<LatLng> drawWaypoints(List<LatLng> taps, DrawShape shape) {
  if (taps.length < 2) return List.of(taps);
  return switch (shape) {
    DrawShape.open => List.of(taps),
    DrawShape.loop => distanceMeters(taps.first, taps.last) < 30 ? List.of(taps) : [...taps, taps.first],
    DrawShape.outAndBack => [...taps, ...taps.reversed.skip(1)],
  };
}

/// Hemelsbreed (voor een snelle schatting voordat de planner antwoordt).
double straightLength(List<LatLng> pts) {
  var m = 0.0;
  for (var i = 1; i < pts.length; i++) {
    m += distanceMeters(pts[i - 1], pts[i]);
  }
  return m;
}

import 'geo.dart';

/// Afstanden voor de privacyzone (meters rond start en finish die niemand ziet).
const privacyZoneOptions = [200, 500, 1000];
const privacyZoneDefault = 500;

/// Maakt een route klaar om met anderen te delen: alle punten binnen [meters] van de start
/// of de finish gaan eraf (zo is niet te zien waar je woont of begint), en de route wordt
/// vereenvoudigd tot hooguit [maxPoints] punten.
///
/// Geeft null als er na het knippen te weinig over is (bijv. een korte run rond je huis):
/// dan wordt de run zonder kaart gedeeld.
String? privacyTrimmedPolyline(String? polyline, {int meters = privacyZoneDefault, int maxPoints = 400}) {
  if (polyline == null || polyline.isEmpty) return null;
  final pts = decodePolyline(polyline);
  if (pts.length < 2) return null;
  final kept = privacyTrimmedPoints(pts, meters: meters);
  if (kept.length < 2) return null;
  // Te weinig zichtbaar om iets aan te hebben (minder dan 300 m)? Dan liever geen kaart.
  var length = 0.0;
  for (var i = 1; i < kept.length; i++) {
    length += distanceMeters(kept[i - 1], kept[i]);
  }
  if (length < 300) return null;
  return encodePolyline(_thin(kept, maxPoints));
}

/// Alle punten die verder dan [meters] van zowel de start als de finish liggen.
/// Ook als je halverwege langs huis loopt, verdwijnt dat stuk.
List<LatLng> privacyTrimmedPoints(List<LatLng> pts, {int meters = privacyZoneDefault}) {
  if (pts.length < 2) return const [];
  final start = pts.first;
  final end = pts.last;
  return [
    for (final p in pts)
      if (distanceMeters(p, start) > meters && distanceMeters(p, end) > meters) p,
  ];
}

List<LatLng> _thin(List<LatLng> pts, int max) {
  if (pts.length <= max) return pts;
  final step = pts.length / max;
  return [for (var i = 0; i < max; i++) pts[(i * step).floor()], pts.last];
}

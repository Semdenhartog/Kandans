import '../data/models/models.dart';
import 'geo.dart';
import 'gpx_parser.dart';
import 'route_geometry.dart';

/// Dezelfde route andersom (punt 70): het spoor omgekeerd, het hoogteprofiel gespiegeld en de
/// hoogtemeters opnieuw geteld (wat eerst afdaling was, is nu klim). Strava-routes worden een eigen route.
RunRoute reversedRoute(RunRoute r, {String suffix = '(andersom)'}) {
  final track = decodePolyline(r.polyline).reversed.toList();
  final profile = reverseProfile(r.profileOrKmPoints);
  double? eleAt(double meters) {
    if (profile.length < 2) return null;
    if (meters <= profile.first.meters) return profile.first.ele;
    for (var i = 1; i < profile.length; i++) {
      final a = profile[i - 1], b = profile[i];
      if (meters <= b.meters) {
        final span = b.meters - a.meters;
        return span <= 0 ? b.ele : a.ele + (b.ele - a.ele) * (meters - a.meters) / span;
      }
    }
    return profile.last.ele;
  }

  final base = r.name.endsWith(suffix) ? r.name.substring(0, r.name.length - suffix.length).trim() : '${r.name} $suffix';
  final built = buildRoute(track, name: base, source: r.source == 'strava' ? 'drawn' : r.source);
  final pace = r.estimatedDurationSeconds != null && r.distanceMeters > 0 ? r.estimatedDurationSeconds! / (r.distanceMeters / 1000) : 360.0;
  return RunRoute(
    name: built.name,
    source: built.source,
    distanceMeters: built.distanceMeters,
    startLatitude: built.startLatitude,
    startLongitude: built.startLongitude,
    polyline: built.polyline,
    elevationGainMeters: profile.length >= 3 ? double.parse(profileAscent(profile).toStringAsFixed(1)) : null,
    estimatedDurationSeconds: (built.distanceMeters / 1000 * pace).round(),
    points: [
      for (final p in built.points)
        RoutePoint(latitude: p.latitude, longitude: p.longitude, kmMarker: p.kmMarker, bearing: p.bearing, elevation: eleAt(p.kmMarker * 1000)),
    ],
    elevationProfile: profile,
  );
}

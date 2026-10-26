import 'geo.dart';

/// Een route delen als link: naam en vorm zitten in de link zelf (geen account of server nodig).
///
/// Website: `<site>/route.html#n=<naam>&p=<polyline>` toont de route op een kaart;
/// app: `runwise://app/route-delen?n=<naam>&p=<polyline>` opent "Route opslaan".
class SharedRoute {
  const SharedRoute(this.name, this.points);
  final String name;
  final List<LatLng> points;

  /// Maximaal aantal punten in een link (houdt de link kort genoeg voor WhatsApp en sms).
  static const maxPoints = 350;

  /// Punten om de zoveel overslaan tot er hooguit [maxPoints] over zijn (begin en eind blijven).
  static List<LatLng> thin(List<LatLng> pts) {
    if (pts.length <= maxPoints) return pts;
    final step = pts.length / (maxPoints - 1);
    return [for (var i = 0; i < maxPoints - 1; i++) pts[(i * step).floor()], pts.last];
  }

  String get _query => 'n=${Uri.encodeQueryComponent(name)}&p=${Uri.encodeQueryComponent(encodePolyline(thin(points)))}';

  /// Link naar de webpagina (werkt ook zonder app).
  String webLink(String siteUrl) => '$siteUrl/route.html#$_query';

  /// Link die de app direct opent.
  String get appLink => 'runwise://app/route-delen?$_query';

  /// Uit de parameters van een link; null als er geen bruikbare route in zit.
  static SharedRoute? fromParams(Map<String, String> q) {
    final p = q['p'];
    if (p == null || p.isEmpty) return null;
    final pts = decodePolyline(p);
    if (pts.length < 2) return null;
    final name = (q['n'] ?? '').trim();
    return SharedRoute(name.isEmpty ? 'Gedeelde route' : (name.length > 60 ? name.substring(0, 60) : name), pts);
  }
}

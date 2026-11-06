import 'geo.dart';

/// Een route delen als link: naam en vorm zitten in de link zelf (geen account of server nodig).
///
/// Website: `<site>/route.html#n=<naam>&p=<polyline>` toont de route op een kaart;
/// app: `runwise://app/route-delen?n=<naam>&p=<polyline>` opent "Route opslaan".
class SharedRoute {
  const SharedRoute(this.name, this.points, {this.ascent, this.elevations = const []});
  final String name;
  final List<LatLng> points;

  /// Meters omhoog en een grof hoogteprofiel (hooguit [maxElevations] waarden, gelijk verdeeld over
  /// de route), zodat de ontvanger vóór het openen van de app ziet hoe zwaar hij is (punt 75).
  final double? ascent;
  final List<double> elevations;

  static const maxElevations = 48;

  /// Hoogteprofiel terugbrengen tot [maxElevations] gelijk verdeelde waarden.
  static List<double> sampleProfile(List<({double meters, double ele})> profile) {
    if (profile.length < 3) return const [];
    final total = profile.last.meters;
    if (total <= 0) return const [];
    final out = <double>[];
    var j = 0;
    for (var i = 0; i < maxElevations; i++) {
      final m = total * i / (maxElevations - 1);
      while (j < profile.length - 2 && profile[j + 1].meters < m) {
        j++;
      }
      final a = profile[j], b = profile[j + 1];
      final span = b.meters - a.meters;
      out.add(span <= 0 ? b.ele : a.ele + (b.ele - a.ele) * ((m - a.meters) / span).clamp(0, 1));
    }
    return out;
  }

  /// Maximaal aantal punten in een link (houdt de link kort genoeg voor WhatsApp en sms).
  static const maxPoints = 350;

  /// Punten om de zoveel overslaan tot er hooguit [maxPoints] over zijn (begin en eind blijven).
  static List<LatLng> thin(List<LatLng> pts) {
    if (pts.length <= maxPoints) return pts;
    final step = pts.length / (maxPoints - 1);
    return [for (var i = 0; i < maxPoints - 1; i++) pts[(i * step).floor()], pts.last];
  }

  String get _query => [
        'n=${Uri.encodeQueryComponent(name)}',
        'p=${Uri.encodeQueryComponent(encodePolyline(thin(points)))}',
        if (ascent != null) 'h=${ascent!.round()}',
        if (elevations.length >= 3) 'e=${elevations.map((e) => e.round()).join('.')}',
      ].join('&');

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
    final h = double.tryParse(q['h'] ?? '');
    final e = [for (final x in (q['e'] ?? '').split('.')) if (double.tryParse(x) case final v?) v];
    return SharedRoute(name.isEmpty ? 'Gedeelde route' : (name.length > 60 ? name.substring(0, 60) : name), pts,
        ascent: h, elevations: e.length >= 3 ? e.take(maxElevations).toList() : const []);
  }
}

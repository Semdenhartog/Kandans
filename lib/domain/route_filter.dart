/// Lengte-groepen om routes snel te filteren.
enum RouteLength {
  all('Alle'),
  short('Tot 5 km'),
  medium('5–10 km'),
  long('Meer dan 10 km');

  const RouteLength(this.label);
  final String label;

  bool matches(double meters) => switch (this) {
        RouteLength.all => true,
        RouteLength.short => meters < 5000,
        RouteLength.medium => meters >= 5000 && meters <= 10000,
        RouteLength.long => meters > 10000,
      };
}

enum RouteSort {
  recent('Nieuwste eerst'),
  shortest('Kortste eerst'),
  longest('Langste eerst'),
  name('Op naam');

  const RouteSort(this.label);
  final String label;
}

/// Zoekt, filtert en sorteert routes. [name], [meters] en [favorite] halen de gegevens uit een route,
/// zodat dit zonder de app getest kan worden.
List<T> filterRoutes<T>(
  List<T> routes, {
  required String Function(T) name,
  required double Function(T) meters,
  required bool Function(T) favorite,
  String query = '',
  bool favoritesOnly = false,
  RouteLength length = RouteLength.all,
  RouteSort sort = RouteSort.recent,
}) {
  final q = query.trim().toLowerCase();
  final out = [
    for (final r in routes)
      if ((q.isEmpty || name(r).toLowerCase().contains(q)) && (!favoritesOnly || favorite(r)) && length.matches(meters(r))) r
  ];
  switch (sort) {
    case RouteSort.recent:
      break; // Zoals de database ze geeft (nieuwste eerst).
    case RouteSort.shortest:
      out.sort((a, b) => meters(a).compareTo(meters(b)));
    case RouteSort.longest:
      out.sort((a, b) => meters(b).compareTo(meters(a)));
    case RouteSort.name:
      out.sort((a, b) => name(a).toLowerCase().compareTo(name(b).toLowerCase()));
  }
  // Favorieten bovenaan (behalve als je op naam of lengte sorteert).
  if (sort == RouteSort.recent) {
    final fav = [for (final r in out) if (favorite(r)) r];
    final rest = [for (final r in out) if (!favorite(r)) r];
    return [...fav, ...rest];
  }
  return out;
}

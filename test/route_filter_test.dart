import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/route_filter.dart';

typedef R = ({String name, double m, bool fav});

void main() {
  const routes = <R>[
    (name: 'Bosrondje', m: 4200, fav: false),
    (name: 'Dijk lang', m: 15000, fav: true),
    (name: 'Rondje dorp', m: 7000, fav: false),
  ];
  List<String> run({String q = '', bool fav = false, RouteLength l = RouteLength.all, RouteSort s = RouteSort.recent}) =>
      filterRoutes<R>(routes, name: (r) => r.name, meters: (r) => r.m, favorite: (r) => r.fav, query: q, favoritesOnly: fav, length: l, sort: s)
          .map((r) => r.name)
          .toList();

  test('zoeken, filteren en sorteren', () {
    expect(run(), ['Dijk lang', 'Bosrondje', 'Rondje dorp']); // favoriet bovenaan
    expect(run(q: 'ronDJE'), ['Bosrondje', 'Rondje dorp']);
    expect(run(fav: true), ['Dijk lang']);
    expect(run(l: RouteLength.short), ['Bosrondje']);
    expect(run(l: RouteLength.medium), ['Rondje dorp']);
    expect(run(s: RouteSort.shortest), ['Bosrondje', 'Rondje dorp', 'Dijk lang']);
    expect(run(s: RouteSort.name), ['Bosrondje', 'Dijk lang', 'Rondje dorp']);
  });
}

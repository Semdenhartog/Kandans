import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/shared/art/wolkje.dart';

HourWeather _w({double t = 12, double? p, double wind = 10, int? code, bool day = true}) =>
    HourWeather(time: DateTime(2026, 11, 10, 12), temperature: t, precipitation: p, windSpeed: wind, weatherCode: code, isDay: day);

void main() {
  test('bui volgt het weer', () {
    expect(wolkjeVoorWeer(null), WolkjeMood.gewoon);
    expect(wolkjeVoorWeer(_w(p: 1.2, code: 61)), WolkjeMood.regen);
    expect(wolkjeVoorWeer(_w(t: 0)), WolkjeMood.koud);
    expect(wolkjeVoorWeer(_w(code: 73, t: 4)), WolkjeMood.koud);
    expect(wolkjeVoorWeer(_w(day: false)), WolkjeMood.nacht);
    expect(wolkjeVoorWeer(_w(wind: 38)), WolkjeMood.wind);
    expect(wolkjeVoorWeer(_w(t: 24, code: 1)), WolkjeMood.zon);
    expect(wolkjeVoorWeer(_w()), WolkjeMood.gewoon);
  });

  test('raster is 18 x 16 met gouden rand en ogen', () {
    for (final m in WolkjeMood.values) {
      for (final stap in [0, 1]) {
        final px = wolkjePixels(m, stap: stap);
        expect(px.length, 16);
        expect(px.every((r) => r.length == 18), isTrue);
      }
    }
    final px = wolkjePixels(WolkjeMood.gewoon);
    expect(px[6][5], const Color(0xFF211A13));
    expect(px[0][7], const Color(0xFFB8955F));
    expect(px[0][0], isNull);
  });

  testWidgets('tekent en staat stil zonder animatie', (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Directionality(textDirection: TextDirection.ltr, child: Center(child: Wolkje(mood: WolkjeMood.regen))),
    ));
    expect(find.byType(Wolkje), findsOneWidget);
    expect(tester.getSize(find.byType(Wolkje)), const Size(72, 64));
  });

  testWidgets('elke hoek van Cloudy opent de coach', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Center(child: Wolkje(size: 52, opensCoach: true)))),
      GoRoute(path: '/coach', builder: (_, _) => const Scaffold(body: Text('coach-scherm'))),
    ]);
    final plek = find.byType(Wolkje);
    for (final hoek in [Alignment.topLeft, Alignment.topRight, Alignment.bottomLeft, Alignment.bottomRight, Alignment.center]) {
      router.go('/');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final r = tester.getRect(plek);
      await tester.tapAt(Offset(r.left + (hoek.x + 1) / 2 * (r.width - 2) + 1, r.top + (hoek.y + 1) / 2 * (r.height - 2) + 1));
      await tester.pumpAndSettle();
      expect(find.text('coach-scherm'), findsOneWidget, reason: 'tik op $hoek');
    }
  });
}

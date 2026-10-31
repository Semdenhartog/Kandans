import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/run_coach.dart';
import 'package:runwise/domain/run_streams.dart';
import 'package:runwise/features/community/runner_avatar.dart';
import 'package:runwise/shared/art/best_moment_demo.dart';
import 'package:runwise/shared/art/exercise_figure.dart';
import 'package:runwise/shared/art/landscape.dart';
import 'package:runwise/shared/art/runner.dart';
import 'package:runwise/shared/art/sun_arc.dart';
import 'package:runwise/shared/art/weather_icon.dart';

void main() {
  test('weercode naar plaatje', () {
    expect(glyphFor(0), WeatherGlyph.sun);
    expect(glyphFor(0, day: false), WeatherGlyph.moon);
    expect(glyphFor(2), WeatherGlyph.partly);
    expect(glyphFor(3), WeatherGlyph.cloud);
    expect(glyphFor(45), WeatherGlyph.fog);
    expect(glyphFor(53), WeatherGlyph.drizzle);
    expect(glyphFor(63), WeatherGlyph.rain);
    expect(glyphFor(81), WeatherGlyph.rain);
    expect(glyphFor(73), WeatherGlyph.snow);
    expect(glyphFor(95), WeatherGlyph.thunder);
  });

  test('seizoenen', () {
    expect(Season.of(DateTime(2026, 11, 2)).fog, isTrue);
    expect(Season.of(DateTime(2026, 11, 2)).fallingLeaves, isTrue);
    expect(Season.of(DateTime(2026, 4, 2)).tulips, isTrue);
    expect(Season.of(DateTime(2026, 8, 2)).heather, isTrue);
    expect(Season.of(DateTime(2027, 1, 2)).snow, isTrue);
    expect(Season.of(DateTime(2026, 7, 2)).bareTrees, isFalse);
  });

  testWidgets('tekeningen bouwen zonder fouten', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          for (final m in [1, 4, 8, 10, 11]) SizedBox(height: 120, child: KadansLandscape(date: DateTime(2026, m, 5))),
          for (final c in [0, 2, 3, 45, 53, 63, 73, 95]) AnimatedWeatherIcon(code: c),
          const RunnerFigure(),
          SunArc(start: DateTime(2026, 11, 2, 16, 30), minutes: 60, lat: 52.1, lon: 5.6),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  test('oefening naar beweging', () {
    expect(motionFor('Kuitheffen'), Motion.calfRaise);
    expect(motionFor('Kuit tegen de muur'), Motion.wallStretch);
    expect(motionFor('Bilbrug'), Motion.bridge);
    expect(motionFor('Eenbenige bilbrug'), Motion.bridge);
    expect(motionFor('Zijplank'), Motion.plank);
    expect(motionFor('Uitvalspas met draai'), Motion.lunge);
    expect(motionFor('Squat naar tenen'), Motion.squat);
    expect(motionFor('Knieheffen op de plaats'), Motion.highKnees);
    expect(motionFor('Hakken naar billen'), Motion.buttKick);
    expect(motionFor('Beenzwaai opzij'), Motion.legSwing);
    expect(motionFor('Vogel-hond'), Motion.birdDog);
    expect(motionFor('Neerwaartse hond'), Motion.dog);
    expect(motionFor('Jumping jacks'), Motion.jacks);
    expect(motionFor('Iets onbekends'), Motion.stand);
  });

  test('ghost: hoe ver was je record na zoveel seconden', () {
    final g = GhostRace(const RunStreams(time: [0, 100, 200, 300], distance: [0, 300, 650, 1000]));
    expect(g.distanceAt(150), closeTo(475, 0.1));
    expect(g.distanceAt(0), isNull);
    expect(g.distanceAt(999), 1000);
  });

  test('omslagkeuze naar seizoen', () {
    expect(coverDate('hei').month, 8);
    expect(coverDate('winter').month, 1);
    expect(coverDate('auto').month, DateTime.now().month);
  });

  testWidgets('oefenfiguren en uitleg-animatie bouwen zonder fouten', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          for (final m in ['Kuitheffen', 'Bilbrug', 'Plank', 'Neerwaartse hond', 'Vogel-hond', 'Uitvalspas', 'Squat', 'Beenzwaai', 'Ademhaling', 'Heupcirkels', 'Armcirkels'])
            SizedBox(height: 120, child: ExerciseFigure(name: m)),
          const BestMomentDemo(),
          const RunnerAvatar('Sem', style: AvatarStyle(icon: 'fire', color: 3)),
          const RunnerAvatar('Anna', style: AvatarStyle()),
        ]),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 700));
    }
    expect(tester.takeException(), isNull);
  });
}

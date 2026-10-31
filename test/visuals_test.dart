import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/zones.dart';
import 'package:runwise/features/races/pace_band.dart';

void main() {
  testWidgets('tempobandje wordt een PNG-plaatje', (tester) async {
    final plan = pacingPlan(10000, 50 * 60, PacingStrategy.even);
    final png = await tester.runAsync(() => paceBandPng(title: 'Test 10 km', subtitle: 'doel 50:00', plan: plan));
    expect(png, isNotNull);
    expect(png!.sublist(1, 4), 'PNG'.codeUnits);
    expect(png.length, greaterThan(1000));
  });
}

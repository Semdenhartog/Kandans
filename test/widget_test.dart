import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/route_geometry.dart';
import 'package:runwise/features/routes/elevation_profile.dart';
import 'package:runwise/shared/config_missing_app.dart';

void main() {
  testWidgets('toont uitleg als Supabase niet is ingesteld', (tester) async {
    await tester.pumpWidget(const ConfigMissingApp());
    expect(find.text('RunWise is nog niet ingesteld'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('hoogteprofiel tekent lijn, vlak en labels (vlak rondje uit km-punten)', (tester) async {
    const kms = [0.0, 1.096, 2.019, 3.009, 4.109, 5.049, 6.001, 7.003, 8.01, 9.038, 9.329];
    const ele = [9.5, 9.3, 11.0, 12.9, 10.0, 9.3, 9.0, 10.0, 9.0, 8.0, 9.5];
    final profile = [for (var i = 0; i < kms.length; i++) ElevationSample(kms[i] * 1000, ele[i])];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(width: 360, child: ElevationProfileChart(profile: profile))),
    ));
    expect(tester.takeException(), isNull);
    final paint = find.descendant(of: find.byType(ElevationProfileChart), matching: find.byType(CustomPaint)).last;
    expect(tester.getSize(paint).height, 120);
    expect(paint, paints..line()..line()..path()..path());
    expect(find.text('6 m omhoog'), findsOneWidget);
  });
}

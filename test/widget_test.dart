import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/shared/config_missing_app.dart';

void main() {
  testWidgets('toont uitleg als Supabase niet is ingesteld', (tester) async {
    await tester.pumpWidget(const ConfigMissingApp());
    expect(find.text('RunWise is nog niet ingesteld'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}

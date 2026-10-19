import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:runwise/main.dart' as app;

/// Start de echte app op een Android-emulator en controleert dat het inlogscherm verschijnt
/// (zonder crash bij het opstarten van Supabase, meldingen, vergrendeling en hartslagband).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app start en toont het inlogscherm', (tester) async {
    app.main();
    final title = find.text('Log in op RunWise.');
    for (var i = 0; i < 80 && title.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(title, findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

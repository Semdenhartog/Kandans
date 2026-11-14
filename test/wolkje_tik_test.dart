import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runwise/shared/art/wolkje.dart';

void main() {
  testWidgets('Cloudy met opensCoach opent de coach', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Center(child: Wolkje(size: 40, animate: false, opensCoach: true)))),
      GoRoute(path: '/coach', builder: (_, __) => const Scaffold(body: Text('coach-scherm'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('coach-scherm'), findsNothing);
    await tester.tap(find.byType(Wolkje));
    await tester.pumpAndSettle();
    expect(find.text('coach-scherm'), findsOneWidget);
  });

  testWidgets('Cloudy zonder opensCoach is niet tikbaar', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: Wolkje(size: 40, animate: false)))));
    expect(find.byType(GestureDetector), findsNothing);
  });
}

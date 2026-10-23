import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/core/supabase.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/data/repositories/repositories.dart';
import 'package:runwise/data/services/pending_runs.dart';
import 'package:runwise/features/activities/trim_run_screen.dart';
import 'package:runwise/shared/home_shell.dart' show PendingRunsBanner;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository die het verloop uit het geheugen geeft in plaats van uit Supabase.
class _FakeRepo extends RunWiseRepository {
  _FakeRepo(this.streams) : super(SupabaseClient('https://voorbeeld.supabase.co', 'anon'));
  final Map<String, dynamic>? streams;

  @override
  Future<Map<String, dynamic>?> activityStreams(String activityId) async => streams;
}

Widget _app(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: [
        supabaseProvider.overrideWithValue(SupabaseClient('https://voorbeeld.supabase.co', 'anon')),
        ...overrides,
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('balk: runs die wachten op internet', () {
    tearDown(() => PendingRunStore.count.value = 0);

    // De balk gebruikt geen Supabase; zonder nep-verbinding blijven er geen timers hangen.
    Widget banner() => const ProviderScope(child: MaterialApp(home: Scaffold(body: PendingRunsBanner())));

    testWidgets('verborgen zonder wachtende runs', (t) async {
      PendingRunStore.count.value = 0;
      await t.pumpWidget(banner());
      expect(find.textContaining('wacht'), findsNothing);
      await _settle(t);
    });

    testWidgets('telt mee en verdwijnt weer', (t) async {
      PendingRunStore.count.value = 1;
      await t.pumpWidget(banner());
      expect(find.text('1 run wacht op internet'), findsOneWidget);
      expect(find.text('Opnieuw'), findsOneWidget);
      PendingRunStore.count.value = 2;
      await t.pump();
      expect(find.text('2 runs wachten op internet'), findsOneWidget);
      PendingRunStore.count.value = 0;
      await t.pump();
      expect(find.textContaining('wacht'), findsNothing);
      await _settle(t);
    });
  });

  group('run bijsnijden', () {
    final run = Activity(
      id: 'a1',
      startedAt: DateTime(2026, 10, 22, 18),
      distanceMeters: 900,
      movingTimeSeconds: 300,
      source: 'runwise',
    );

    testWidgets('toont afstand, tijd en de knop', (t) async {
      final streams = {
        't': [for (var i = 0; i <= 100; i++) i * 3.0],
        'd': [for (var i = 0; i <= 100; i++) i * 9.0],
      };
      await t.pumpWidget(_app(TrimRunScreen(activity: run), overrides: [repositoryProvider.overrideWithValue(_FakeRepo(streams))]));
      await _settle(t);
      expect(t.takeException(), isNull);
      expect(find.text('NA HET BIJSNIJDEN'), findsOneWidget);
      expect(find.byType(RangeSlider), findsOneWidget);
      expect(find.text('Bijsnijden en opslaan'), findsOneWidget);
      expect(find.textContaining('was '), findsWidgets);
    });

    testWidgets('zonder verloop een duidelijke uitleg', (t) async {
      await t.pumpWidget(_app(TrimRunScreen(activity: run), overrides: [repositoryProvider.overrideWithValue(_FakeRepo(null))]));
      await _settle(t);
      expect(find.textContaining('geen verloop per seconde'), findsOneWidget);
      expect(find.text('Bijsnijden en opslaan'), findsNothing);
    });
  });
}

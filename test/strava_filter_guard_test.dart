import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Vaste regel 2: Strava-data gaat niet naar de coach en niet naar andere gebruikers.
/// Deze test bewaakt dat de filters op de plekken waar dat gebeurt niet per ongeluk verdwijnen.
void main() {
  const places = [
    'supabase/functions/coach/index.ts',
    'supabase/functions/community/index.ts',
    'supabase/migrations/0034_volgen_en_runs_delen.sql',
    'supabase/migrations/0037_samen_extra.sql',
  ];
  for (final p in places) {
    test('Strava-filter staat nog in $p', () {
      final src = File(p).readAsStringSync();
      expect(src.contains('viastrava-'), isTrue, reason: 'filter op external_id viastrava- ontbreekt');
      expect(RegExp(r"strava").hasMatch(src), isTrue);
    });
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/data/services/community_feed_service.dart';
import 'package:runwise/data/services/sound_service.dart';
import 'package:runwise/data/services/together_service.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/route_geometry.dart';
import 'package:runwise/domain/route_reverse.dart';
import 'package:runwise/domain/route_share.dart';
import 'package:runwise/domain/run_coach.dart';
import 'package:runwise/features/record/record_celebration_screen.dart';
import 'package:runwise/features/routes/route_flyover_screen.dart';

void main() {
  test('tempo-alarm met bandbreedte: buiten 5:20–5:40 na 10 s een waarschuwing', () {
    final c = PaceCoach.band(320, 340);
    expect(c.band, isTrue);
    final said = <String>[];
    for (var t = 0; t < 15; t++) {
      if (c.update(t.toDouble(), 360) case final s?) said.add(s);
    }
    expect(said, hasLength(1));
    expect(said.first, startsWith('Te langzaam'));
    expect(said.first, contains('tot'));
    // Binnen de band: niets.
    final ok = PaceCoach.band(320, 340);
    for (var t = 0; t < 40; t++) {
      expect(ok.update(t.toDouble(), 330), isNull);
    }
    // Te snel.
    final fast = PaceCoach.band(320, 340);
    String? last;
    for (var t = 0; t < 15; t++) {
      last = fast.update(t.toDouble(), 300) ?? last;
    }
    expect(last, startsWith('Te snel'));
  });

  test('route andersom: spoor omgekeerd, klim wordt afdaling', () {
    final pts = [for (var i = 0; i <= 40; i++) LatLng(52.0 + i * 0.0005, 5.0)];
    // Eerste helft 40 m omhoog, daarna vlak.
    final profile = [
      for (var i = 0; i <= 40; i++) ElevationSample(i * 55.6, i <= 20 ? i * 2.0 : 40.0),
    ];
    final r = RunRoute(
      name: 'Heuvel',
      source: 'drawn',
      distanceMeters: 2224,
      startLatitude: pts.first.lat,
      startLongitude: pts.first.lon,
      polyline: encodePolyline(pts),
      elevationGainMeters: profileAscent(profile),
      elevationProfile: profile,
    );
    final rev = reversedRoute(r);
    expect(rev.name, 'Heuvel (andersom)');
    expect(rev.startLatitude, closeTo(pts.last.lat, 1e-4));
    expect(rev.elevationProfile.first.ele, 40);
    expect(rev.elevationProfile.last.ele, 0);
    expect(r.elevationGainMeters, greaterThan(30));
    expect(rev.elevationGainMeters, lessThan(5));
    // Nog een keer omdraaien geeft de oorspronkelijke naam terug.
    expect(reversedRoute(rev).name, 'Heuvel');
  });

  test('deel-link met hoogtemeters en profiel heen en terug', () {
    final pts = [for (var i = 0; i < 20; i++) LatLng(52 + i * 0.001, 5)];
    final elevations = SharedRoute.sampleProfile([for (var i = 0; i <= 10; i++) (meters: i * 100.0, ele: i * 3.0)]);
    expect(elevations, hasLength(SharedRoute.maxElevations));
    expect(elevations.first, 0);
    expect(elevations.last, closeTo(30, 0.01));
    final link = SharedRoute('Dijk', pts, ascent: 31.6, elevations: elevations).appLink;
    final back = SharedRoute.fromParams(Uri.parse(link).queryParameters)!;
    expect(back.ascent, 32);
    expect(back.elevations, hasLength(SharedRoute.maxElevations));
    expect(SharedRoute.fromParams(Uri.parse(SharedRoute('X', pts).appLink).queryParameters)!.elevations, isEmpty);
  });

  test('vlieg over: positie en kijkrichting langs de route', () {
    final track = [const LatLng(52, 5), const LatLng(52.01, 5), const LatLng(52.01, 5.02)];
    final cum = <double>[0];
    for (var i = 1; i < track.length; i++) {
      cum.add(cum.last + distanceMeters(track[i - 1], track[i]));
    }
    final start = flyoverPose(track, cum, 0);
    expect(start.at.lat, 52);
    expect(start.bearing, closeTo(0, 2)); // eerst naar het noorden
    final end = flyoverPose(track, cum, 1);
    expect(end.at.lon, closeTo(5.02, 1e-6));
    expect(end.bearing, closeTo(90, 2)); // aan het eind naar het oosten
  });

  test('piepje is een geldige wav', () {
    final w = toneWav(880, 0.1);
    expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(w.sublist(8, 12)), 'WAVE');
    expect(w.length, 44 + 2205 * 2);
  });

  test('snelle reacties en @vermeldingen', () {
    final c = CommunityComment.fromJson({
      'id': 1,
      'body': 'Top @Anna_B!',
      'created_at': '2026-11-06T10:00:00Z',
      'nickname': 'Sem',
      'reactions': {'🔥': 2},
      'my_reactions': ['🔥'],
    });
    expect(c.reactions['🔥'], 2);
    final off = c.toggled('🔥');
    expect(off.reactions['🔥'], 1);
    expect(off.myReactions, isEmpty);
    final on = off.toggled('👏');
    expect(on.reactions['👏'], 1);
    expect(on.myReactions, {'👏'});
    expect(mentionPattern.allMatches('hoi @anna_b en @x en @piet.k').map((m) => m.group(1)).toList(), ['anna_b', 'piet.k']);
  });

  test('groepsrun uit de database', () {
    final g = GroupRun.fromJson({
      'id': 4,
      'starts_at': '2026-11-08T08:30:00Z',
      'place': 'Park',
      'distance_km': 8,
      'planner': 'Sem',
      'going': 2,
      'not_going': 1,
      'going_names': ['Sem', 'Anna'],
      'my_answer': null,
      'can_delete': true,
    });
    expect(g.goingNames, ['Sem', 'Anna']);
    expect(g.distanceKm, 8);
    expect(g.myAnswer, isNull);
    expect(g.canDelete, isTrue);
  });

  test('record: hoeveel sneller', () {
    expect(recordGainText((label: '5 km', meters: 5000, seconds: 1412, previous: 1449)), contains('37 s'));
    expect(recordGainText((label: '5 km', meters: 5000, seconds: 1412, previous: null)), isNull);
  });
}

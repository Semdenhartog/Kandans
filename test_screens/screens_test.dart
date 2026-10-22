// Schermafbeeldingen van de belangrijkste schermen met voorbeeldgegevens.
// Draait in de cloud (workflow "Schermen"): flutter test test_screens --update-goldens
// De plaatjes komen in test_screens/goldens en worden als artefact bewaard, zodat de
// layout bekeken kan worden zonder telefoon. Geen echte gebruikersgegevens.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:runwise/core/supabase.dart';
import 'package:runwise/core/theme.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/data/repositories/repositories.dart';
import 'package:runwise/data/services/air_quality_service.dart';
import 'package:runwise/data/services/location_service.dart';
import 'package:runwise/data/services/rain_service.dart';
import 'package:runwise/data/services/heart_rate_service.dart';
import 'package:runwise/data/services/run_recorder_service.dart';
import 'package:runwise/data/services/sync_service.dart';
import 'package:runwise/domain/run_recorder.dart';
import 'package:runwise/domain/route_turns.dart';
import 'package:runwise/domain/availability.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/readiness.dart';
import 'package:runwise/domain/run_warnings.dart';
import 'package:runwise/domain/training_plan.dart';
import 'package:runwise/features/activities/activities_screen.dart';
import 'package:runwise/features/activities/activity_detail_screen.dart';
import 'package:runwise/features/activities/badges_screen.dart';
import 'package:runwise/features/activities/fitness_screen.dart';
import 'package:runwise/features/activities/strength_screen.dart';
import 'package:runwise/features/activities/year_story_screen.dart';
import 'package:runwise/domain/strength.dart';
import 'package:runwise/features/coach/coach_screen.dart';
import 'package:runwise/features/coach/paywall_screen.dart';
import 'package:runwise/features/dashboard/dashboard_providers.dart';
import 'package:runwise/features/dashboard/dashboard_screen.dart';
import 'package:runwise/features/dashboard/month_challenge_card.dart';
import 'package:runwise/features/planner/availability_provider.dart';
import 'package:runwise/features/planner/training_plan_screen.dart';
import 'package:runwise/features/auth/login_screen.dart';
import 'package:runwise/features/onboarding/onboarding_screen.dart';
import 'package:runwise/features/profile/profile_screen.dart';
import 'package:runwise/features/record/record_run_screen.dart';
import 'package:runwise/features/record/run_summary_screen.dart';
import 'package:runwise/domain/badges.dart' as bd;
import 'package:runwise/domain/best_efforts.dart';
import 'package:runwise/domain/run_streams.dart';
import 'package:runwise/features/routes/route_detail_screen.dart';
import 'package:runwise/features/routes/routes_screen.dart';

const _w = 412.0;

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final l = FontLoader(name);
    for (final f in files) {
      l.addFont(rootBundle.load(f));
    }
    await l.load();
  }

  await family('Saira', ['assets/fonts/Saira-Bold.ttf', 'assets/fonts/Saira-ExtraBold.ttf']);
  await family('DMSans', [
    'assets/fonts/DMSans-Regular.ttf',
    'assets/fonts/DMSans-Medium.ttf',
    'assets/fonts/DMSans-SemiBold.ttf',
    'assets/fonts/DMSans-Bold.ttf',
  ]);
  // Ook de standaardletter (Roboto) laten wijzen naar DM Sans, zodat er geen blokjes staan.
  await family('Roboto', ['assets/fonts/DMSans-Regular.ttf', 'assets/fonts/DMSans-Bold.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
      await l.load();
    }
  }
}

// ---------------------------------------------------------------- voorbeeldgegevens

final _now = DateTime.now();
const _home = LatLng(52.14, 5.585);

List<LatLng> _loop(double km, double phase) {
  final r = km / (2 * math.pi) / 111.0;
  return [
    for (var i = 0; i <= 80; i++)
      LatLng(
        _home.lat + r * math.sin(i / 80 * 2 * math.pi + phase) * (1 + 0.15 * math.sin(i / 7)),
        _home.lon + r * 1.6 * math.cos(i / 80 * 2 * math.pi + phase) * (1 + 0.1 * math.cos(i / 5)),
      ),
  ];
}

final _routes = [
  RunRoute(
      id: 'r1',
      name: 'Rondje bos',
      source: 'generated',
      distanceMeters: 8200,
      startLatitude: _home.lat,
      startLongitude: _home.lon,
      polyline: encodePolyline(_loop(8.2, 0)),
      elevationGainMeters: 34,
      estimatedDurationSeconds: 2700,
      isFavorite: true),
  RunRoute(
      id: 'r2',
      name: 'Langs de beek',
      source: 'drawn',
      distanceMeters: 5100,
      startLatitude: _home.lat,
      startLongitude: _home.lon,
      polyline: encodePolyline(_loop(5.1, 1.2)),
      elevationGainMeters: 12,
      estimatedDurationSeconds: 1700),
  RunRoute(
      id: 'r3',
      name: 'Lange duurloop heide',
      source: 'gpx_upload',
      distanceMeters: 16400,
      startLatitude: _home.lat,
      startLongitude: _home.lon,
      polyline: encodePolyline(_loop(16.4, 2.5)),
      elevationGainMeters: 88,
      estimatedDurationSeconds: 5800),
];

final _runs = () {
  final rnd = math.Random(7);
  final out = <Activity>[];
  for (var d = 1; d < 120; d++) {
    if (d % 7 == 2 || d % 7 == 5 || rnd.nextDouble() < 0.12) continue;
    final day = _now.subtract(Duration(days: d));
    final long = day.weekday == DateTime.sunday;
    final km = long ? 12 + rnd.nextDouble() * 6 : 5 + rnd.nextDouble() * 4;
    final pace = (long ? 345 : 320) + rnd.nextDouble() * 30 - (120 - d) * 0.15;
    final route = _routes[rnd.nextInt(3)];
    out.add(Activity(
      id: 'a$d',
      startedAt: DateTime(day.year, day.month, day.day, d.isEven ? 7 : 18, 30),
      distanceMeters: km * 1000,
      movingTimeSeconds: (km * pace).round(),
      source: 'runwise',
      routeId: route.id,
      averageHeartRate: 138 + rnd.nextInt(25),
      elevationGainMeters: 10 + rnd.nextDouble() * 60,
      temperatureCelsius: 8 + rnd.nextDouble() * 14,
      feelsLikeCelsius: 6 + rnd.nextDouble() * 14,
      windSpeedKmh: 8 + rnd.nextDouble() * 25,
      windDirectionDegrees: rnd.nextDouble() * 360,
      humidityPct: 60 + rnd.nextDouble() * 35,
      trackPolyline: route.polyline,
      feel: 1 + rnd.nextInt(3),
      bestEfforts: {'1000': pace * 0.92, '5000': pace * 5 * 0.97, if (km >= 10) '10000': pace * 10},
      aiSummary: out.isEmpty
          ? 'Mooi gelijkmatig gelopen: je laatste kilometers waren zelfs iets sneller dan de eerste. '
              'De wind uit het zuidwesten kostte je op de terugweg zo\'n 8 seconden per km. '
              'Deze run past goed in je opbouw van deze week. Tip: houd je volgende rustige run echt rustig, onder 145 hartslag.'
          : null,
    ));
  }
  return out;
}();

final Map<String, dynamic> _streams = () {
  final t = <double>[], d = <double>[], hr = <double>[], alt = <double>[];
  for (var i = 0; i <= 300; i++) {
    t.add(i * 10.0);
    d.add(i * 10.0 * (1000 / 315) * (1 + 0.04 * math.sin(i / 20)));
    hr.add(130 + 20 * (i / 300) + 5 * math.sin(i / 9));
    alt.add(8 + 6 * math.sin(i / 40));
  }
  return <String, dynamic>{'t': t, 'd': d, 'hr': hr, 'alt': alt};
}();

final _forecast = Forecast(
  latitude: _home.lat,
  longitude: _home.lon,
  hours: [
    for (var h = 0; h < 48; h++)
      () {
        final t = DateTime(_now.year, _now.month, _now.day, _now.hour).add(Duration(hours: h));
        final temp = 11 + 6 * math.sin((t.hour - 9) / 24 * 2 * math.pi);
        return HourWeather(
          time: t,
          temperature: temp,
          feelsLike: temp - 2,
          humidity: 70 + 15 * math.cos(t.hour / 24 * 2 * math.pi),
          precipitationProbability: (t.hour >= 15 && t.hour <= 18) ? 65 : 10,
          precipitation: (t.hour >= 15 && t.hour <= 18) ? 0.8 : 0,
          windSpeed: 12 + 10 * math.sin(t.hour / 24 * 2 * math.pi),
          windDirection: 225,
          windGusts: 30,
          uvIndex: 2,
          weatherCode: (t.hour >= 15 && t.hour <= 18) ? 61 : 2,
          isDay: t.hour > 7 && t.hour < 19,
        );
      }(),
  ],
);

final _plan = buildPlan(
  PlanSetup(
    goalMeters: 10000,
    raceDate: _now.add(const Duration(days: 52)),
    runDays: [1, 3, 4, 6, 7],
    longRunDay: 7,
    currentWeeklyKm: 28,
    thresholdPace: 290,
    goalTimeSeconds: 2880,
  ),
  _now.subtract(const Duration(days: 21)),
);

final _coach = [
  CoachMessage(role: 'user', content: 'Hoe ver moet mijn lange duurloop zijn deze week?', createdAt: _now.subtract(const Duration(minutes: 9))),
  CoachMessage(
      role: 'assistant',
      content: 'Je liep de laatste 4 weken gemiddeld 28 km per week, met als langste 15,8 km.\n\n'
          '- Deze week: **16–17 km** rustig (rond 5:50/km)\n- Zondag wordt 12 °C met weinig wind: prima\n- Volgende week een rustweek: 12 km\n\n'
          'Voel je je moe, dan liever 14 km.',
      createdAt: _now.subtract(const Duration(minutes: 8))),
];

List<Override> _overrides({bool emptyPlan = false}) => [
      supabaseProvider.overrideWithValue(SupabaseClient('https://voorbeeld.supabase.co', 'anon')),
      currentUserProvider.overrideWithValue(null),
      profileProvider.overrideWith((ref) => Profile(id: 'u', firstName: 'Sem', homeLatitude: _home.lat, homeLongitude: _home.lon)),
      activitiesProvider.overrideWith((ref) => _runs),
      routesProvider.overrideWith((ref) => _routes),
      planProvider.overrideWith((ref) => emptyPlan ? const <PlanSession>[] : _plan),
      shoesProvider.overrideWith((ref) => [Shoe(id: 's1', name: 'Novablast 4', isDefault: true), Shoe(id: 's2', name: 'Endorphin Speed')]),
      racesProvider.overrideWith((ref) => [RaceEvent(id: 'w1', name: 'Singelloop', raceDate: _now.add(const Duration(days: 38)), distanceMeters: 10000, goalTimeSeconds: 2880)]),
      coachMessagesProvider.overrideWith((ref) => _coach),
      forecastProvider.overrideWith((ref) => _forecast),
      weekForecastProvider.overrideWith((ref) => _forecast),
      weatherLocationProvider.overrideWith((ref) => Coordinates(_home.lat, _home.lon, 'je locatie')),
      rainNowcastProvider.overrideWith((ref) => null),
      airQualityProvider.overrideWith((ref) => const <AirQuality>[]),
      availabilityProvider.overrideWith((ref) => Availability.always),
      bodySignalsProvider.overrideWith((ref) => const BodySignals(
          sleepHours: 6.4, sleepAvgHours: 7.4, restingHr: 52, restingHrBaseline: 50, hrv: 58, hrvBaseline: 62)),
      healthStatusProvider.overrideWith((ref) => HealthStatus.connected),
      stravaConnectionProvider.overrideWith((ref) => null),
      monthlyGoalProvider.overrideWith((ref) => 120.0),
      activityStreamsProvider(_runs.first.id!).overrideWith((ref) => _streams),
      routeDetailProvider('r1').overrideWith((ref) => _routes.first),
    ];

Future<void> _shot(WidgetTester tester, String name, Widget screen,
    {double height = 2400, bool nav = false, void Function()? after, double textScale = 1, bool emptyPlan = false}) async {
  tester.view.physicalSize = Size(_w * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(emptyPlan: emptyPlan),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Zelfde donkere ondergrond als de app (anders kleuren doorzichtige schermen vreemd in de PNG).
      builder: (context, child) => ColoredBox(
        color: RwColors.background,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: nav ? _FakeShell(child: screen) : screen,
    ),
  ));
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  if (after != null) {
    after();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  // Timers en animaties opruimen.
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(minutes: 2));
  }
}

/// Zelfde onderbalk als de echte app (zonder router).
class _FakeShell extends StatelessWidget {
  const _FakeShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), label: 'Vandaag'),
            NavigationDestination(icon: Icon(Icons.directions_run), label: 'Runs'),
            NavigationDestination(icon: Icon(Icons.route_outlined), label: 'Routes'),
            NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), label: 'Coach'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'Ik'),
          ],
        ),
      );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('nl_NL');
    await initializeDateFormatting('nl');
    Intl.defaultLocale = 'nl_NL';
    await _loadFonts();
  });

  testWidgets('01 vandaag', (t) => _shot(t, '01_vandaag', const DashboardScreen(), height: 2600, nav: true));
  testWidgets('01b vandaag boven', (t) => _shot(t, '01b_vandaag_boven', const DashboardScreen(), height: 915, nav: true));
  testWidgets('02 runs', (t) => _shot(t, '02_runs', const ActivitiesScreen(), height: 1800));
  testWidgets('03 run detail', (t) => _shot(t, '03_run_detail', ActivityDetailScreen(activityId: _runs.first.id!), height: 3200));
  testWidgets('04 routes', (t) => _shot(t, '04_routes', const RoutesScreen(), height: 1600));
  testWidgets('05 coach', (t) => _shot(t, '05_coach', const CoachScreen(), height: 915));
  testWidgets('06 ik', (t) => _shot(t, '06_ik', const ProfileScreen(), height: 2600));
  testWidgets('07 fitheid', (t) => _shot(t, '07_fitheid', const FitnessScreen(), height: 1800));
  testWidgets('08 badges', (t) => _shot(t, '08_badges', const BadgesScreen(), height: 1900));
  testWidgets('10 opnemen start', (t) => _shot(t, '10_opnemen_start', const RecordRunScreen(), height: 915));
  testWidgets('11 opnemen bezig', (t) => _shot(t, '11_opnemen_bezig', const RecordRunScreen(), height: 915, after: () {
        RunRecorderService.instance.view.value = RecorderView(
          status: RecorderStatus.running,
          distance: 5230,
          movingSeconds: 1652,
          currentPace: 309,
          averagePace: 316,
          km: 5,
          gpsAccuracy: 4,
          heartRate: 152,
          hrStatus: HrStatus.connected,
          followRoute: decodePolyline(_routes.first.polyline),
          routeRemaining: 2970,
          ghostDelta: -12,
          nextTurn: const RouteTurn(meters: 2400, point: LatLng(52.15, 5.6), kind: TurnKind.left, angle: -90),
          nextTurnIn: 120,
        );
      }));
  testWidgets('11b afslag nu, groot', (t) => _shot(t, '11b_afslag_groot', const RecordRunScreen(), height: 915, textScale: 1.6, after: () {
        RunRecorderService.instance.view.value = RecorderView(
          status: RecorderStatus.running,
          distance: 5230,
          movingSeconds: 1652,
          currentPace: 309,
          averagePace: 316,
          km: 5,
          gpsAccuracy: 4,
          followRoute: decodePolyline(_routes.first.polyline),
          routeRemaining: 2970,
          nextTurn: const RouteTurn(meters: 2400, point: LatLng(52.15, 5.6), kind: TurnKind.sharpRight, angle: 130),
          nextTurnIn: 15,
        );
      }));
  testWidgets('12 route detail', (t) => _shot(t, '12_route_detail', const RouteDetailScreen(routeId: 'r1'), height: 3000));
  testWidgets('13 inloggen', (t) => _shot(t, '13_inloggen', const LoginScreen(), height: 915));
  testWidgets('14 rondleiding', (t) => _shot(t, '14_rondleiding', const OnboardingScreen(), height: 915));
  testWidgets('15 na je run', (t) {
    final st = RunStreams.fromJson(_streams)!;
    return _shot(
        t,
        '15_na_je_run',
        RunSummaryScreen(
          activity: _runs.first,
          streams: st,
          efforts: bestEfforts(st),
          previousBest: const {1000: (seconds: 999.0, activityId: 'x')},
          badges: bd.computeBadges(_runs).where((b) => b.earned).take(2).toList(),
        ),
        height: 2600);
  });
  testWidgets('20 groot vandaag', (t) => _shot(t, '20_groot_vandaag', const DashboardScreen(), height: 3200, nav: true, textScale: 1.6));
  testWidgets('21 groot opnemen', (t) => _shot(t, '21_groot_opnemen', const RecordRunScreen(), height: 915, textScale: 1.6, after: () {
        RunRecorderService.instance.view.value = RecorderView(
          status: RecorderStatus.running,
          distance: 15230,
          movingSeconds: 5652,
          currentPace: 309,
          averagePace: 316,
          km: 15,
          gpsAccuracy: 4,
          heartRate: 152,
          hrStatus: HrStatus.connected,
        );
      }));
  testWidgets('22 groot runs', (t) => _shot(t, '22_groot_runs', const ActivitiesScreen(), height: 1600, textScale: 1.6));
  testWidgets('23 schema kiezen', (t) => _shot(t, '23_schema_kiezen', const TrainingPlanScreen(), height: 1900, emptyPlan: true));
  testWidgets('24 briefing', (t) => _shot(t, '24_briefing', const _OpenBriefing(), height: 1100));
  testWidgets('25 loopband', (t) => _shot(t, '25_loopband', const RecordRunScreen(), height: 915, after: () {
        RunRecorderService.instance.view.value = RecorderView(
          status: RecorderStatus.running,
          distance: 4120,
          movingSeconds: 1236,
          km: 4,
          indoor: true,
          treadmillKmh: 12,
          heartRate: 148,
          hrStatus: HrStatus.connected,
        );
      }));
  testWidgets('26 kracht', (t) => _shot(t, '26_kracht', const StrengthScreen(), height: 915));
  testWidgets('27 kracht bezig', (t) => _shot(t, '27_kracht_bezig', RoutinePlayerScreen(routine: Routine.all[1]), height: 915));
  testWidgets('28 jaarverhaal', (t) => _shot(t, '28_jaarverhaal', YearStoryScreen(year: _now.year), height: 915));
  testWidgets('29 premium', (t) => _shot(t, '29_premium', const PaywallScreen(), height: 1300));
  // Grote letters (160%): valt er iets uit beeld, dan faalt de stap 'Uit beeld-controle' in screens.yml.
  testWidgets('30 groot opnemen start', (t) {
    // Vorige tests laten een lopende run achter; voor het startscherm terug naar stilstand.
    RunRecorderService.instance.view.value = const RecorderView();
    return _shot(t, '30_groot_opnemen_start', const RecordRunScreen(), height: 915, textScale: 1.6);
  });
  testWidgets('31 groot run detail', (t) => _shot(t, '31_groot_run_detail', ActivityDetailScreen(activityId: _runs.first.id!), height: 3800, textScale: 1.6));
  testWidgets('32 groot routes', (t) => _shot(t, '32_groot_routes', const RoutesScreen(), height: 1900, textScale: 1.6));
  testWidgets('33 groot coach', (t) => _shot(t, '33_groot_coach', const CoachScreen(), height: 915, textScale: 1.6));
  testWidgets('34 groot ik', (t) => _shot(t, '34_groot_ik', const ProfileScreen(), height: 3200, textScale: 1.6));
  testWidgets('09 schema', (t) => _shot(t, '09_schema', const TrainingPlanScreen(), height: 1800));
}

/// Opent de briefing van de eerstvolgende training (voor de schermafbeelding).
class _OpenBriefing extends StatefulWidget {
  const _OpenBriefing();

  @override
  State<_OpenBriefing> createState() => _OpenBriefingState();
}

class _OpenBriefingState extends State<_OpenBriefing> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final next = _plan.firstWhere((s) => s.kind == SessionKind.long && !s.date.isBefore(_now));
      showSessionBriefing(context, next, readinessScore: 57);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

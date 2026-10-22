import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/activities/activities_screen.dart';
import '../features/activities/activity_detail_screen.dart';
import '../features/activities/records_screen.dart';
import '../features/activities/add_activity_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/verify_screen.dart';
import '../features/coach/coach_screen.dart';
import '../features/coach/paywall_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/shoes_screen.dart';
import '../features/profile/strava_return_screen.dart';
import '../features/races/add_race_screen.dart';
import '../features/races/race_detail_screen.dart';
import '../features/races/races_screen.dart';
import '../features/routes/draw_route_screen.dart';
import '../features/routes/generate_route_screen.dart';
import '../features/routes/route_detail_screen.dart';
import '../features/routes/routes_screen.dart';
import '../shared/home_shell.dart';
import 'supabase.dart';

/// Laat GoRouter opnieuw de redirect uitvoeren bij in- of uitloggen.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<AuthState> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

const _publicPaths = {'/login', '/signup', '/verify'};

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  final refresh = _AuthRefresh(auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/today',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final isPublic = _publicPaths.contains(state.matchedLocation);
      if (!loggedIn && !isPublic) return '/login';
      if (loggedIn && isPublic) return '/today';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (c, s) => const SignupScreen()),
      GoRoute(
        path: '/verify',
        builder: (c, s) =>
            VerifyScreen(email: s.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(path: '/premium', builder: (c, s) => const PaywallScreen()),
      // Terugkomst na koppelen met Strava: runwise://app/strava-connected?status=ok
      GoRoute(
        path: '/strava-connected',
        builder: (c, s) => StravaReturnScreen(status: s.uri.queryParameters['status'] ?? 'error'),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/today',
              builder: (c, s) => const DashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/runs',
              builder: (c, s) => const ActivitiesScreen(),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (c, s) => const AddActivityScreen(),
                ),
                GoRoute(
                  path: 'records',
                  builder: (c, s) => const RecordsScreen(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (c, s) => ActivityDetailScreen(activityId: s.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/routes',
              builder: (c, s) => const RoutesScreen(),
              routes: [
                // Vóór ':id', anders wordt 'maken' als route-id gelezen.
                GoRoute(
                  path: 'maken',
                  builder: (c, s) => const GenerateRouteScreen(),
                ),
                GoRoute(
                  path: 'tekenen',
                  builder: (c, s) => const DrawRouteScreen(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (c, s) => RouteDetailScreen(
                      routeId: s.pathParameters['id']!, isNew: s.uri.queryParameters['nieuw'] == '1'),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/coach', builder: (c, s) => const CoachScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/me',
              builder: (c, s) => const ProfileScreen(),
              routes: [
                GoRoute(path: 'shoes', builder: (c, s) => const ShoesScreen()),
                GoRoute(
                  path: 'races',
                  builder: (c, s) => const RacesScreen(),
                  routes: [
                    GoRoute(
                      path: 'new',
                      builder: (c, s) => const AddRaceScreen(),
                    ),
                    GoRoute(
                      path: ':id',
                      builder: (c, s) =>
                          RaceDetailScreen(raceId: s.pathParameters['id']!),
                    ),
                  ],
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});

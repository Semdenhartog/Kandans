import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/services/sync_service.dart';

/// Onderste navigatiebalk met de vijf hoofdtabbladen.
/// Haalt bij het openen (en terugkomen in) de app automatisch nieuwe runs op
/// uit gekoppelde bronnen (horloge via Health Connect, Strava).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoSync();
  }

  void _autoSync() {
    // Stil op de achtergrond; fouten zie je pas als je zelf vernieuwt.
    ref.read(syncServiceProvider).syncAll().ignore();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), label: 'Vandaag'),
          NavigationDestination(icon: Icon(Icons.directions_run), label: 'Runs'),
          NavigationDestination(icon: Icon(Icons.route_outlined), label: 'Routes'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), label: 'Wedstrijden'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Ik'),
        ],
      ),
    );
  }
}

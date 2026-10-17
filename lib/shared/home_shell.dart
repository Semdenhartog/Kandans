import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Onderste navigatiebalk met de vijf hoofdtabbladen.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
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

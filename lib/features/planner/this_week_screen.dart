import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../shared/widgets.dart';
import '../dashboard/extra_cards.dart' show WeekendCard;
import 'roster_screen.dart';
import 'training_plan_screen.dart';
import 'week_planner_screen.dart';

void openThisWeek(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ThisWeekScreen()));

/// Deze week: alles om je week te plannen op één plek (beste momenten, rooster, schema, wedstrijden, weekend).
class ThisWeekScreen extends StatelessWidget {
  const ThisWeekScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Deze week'))),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const WeekPlannerEntry(),
            const SizedBox(height: 12),
            const RosterCard(),
            const SizedBox(height: 12),
            const WeekendCard(),
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                ListTile(
                  leading: TileIcon(Icons.calendar_view_week_outlined),
                  title: Text(tr('Weekplanner')),
                  subtitle: Text(tr('De beste momenten per dag, binnen je looptijden')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openWeekPlanner(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.event_busy_outlined),
                  title: Text(tr('Werkrooster')),
                  subtitle: Text(tr('Nooit een run tijdens je dienst')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openRosterScreen(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.fitness_center_outlined),
                  title: Text(tr('Trainingsschema')),
                  subtitle: Text(tr('Een schema op maat naar je wedstrijd of afstand')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openTrainingPlan(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.flag_outlined),
                  title: Text(tr('Wedstrijden')),
                  subtitle: Text(tr('Je doelen, voorspelde eindtijd en wedstrijdadvies')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/me/races'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../shared/widgets.dart';
import '../activities/badges_screen.dart' show openBadges;
import '../dashboard/bingo_card.dart';
import '../dashboard/extra_cards.dart' show YearGoalCard;
import '../dashboard/month_challenge_card.dart';
import 'challenges.dart';

void openGoals(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GoalsScreen()));

/// Doelen: alle spelvormen op één plek (deze maand, je jaar, bingo, uitdagingen, badges en records)
/// in plaats van verspreid over Vandaag, Ik en Samen.
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Doelen'))),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const MonthChallengeCard(),
            const SizedBox(height: 12),
            const YearGoalCard(),
            const SizedBox(height: 12),
            const ChallengesCard(),
            const SizedBox(height: 12),
            const BingoCardView(),
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                ListTile(
                  leading: TileIcon(Icons.emoji_events_outlined),
                  title: Text(tr('Alle uitdagingen')),
                  subtitle: Text(tr('Doe mee aan een maand- of seizoensuitdaging')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openChallenges(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.military_tech_outlined),
                  title: Text(tr('Badges')),
                  subtitle: Text(tr('Mijlpalen en weerbadges')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openBadges(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.timer_outlined),
                  title: Text(tr('Mijn records')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/runs/records'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

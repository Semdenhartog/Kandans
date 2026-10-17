import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets.dart';

class RacesScreen extends ConsumerWidget {
  const RacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final races = ref.watch(racesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Wedstrijden')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/races/new'),
        icon: const Icon(Icons.add),
        label: const Text('Wedstrijd toevoegen'),
      ),
      body: races.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(racesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.flag_outlined,
              title: 'Nog geen wedstrijd gepland',
              message: 'Voeg je volgende wedstrijd toe. Vanaf ongeveer 2 weken vooraf krijg je '
                  'een voorspelling met het verwachte weer, kleding- en tempo-advies.',
              actionLabel: 'Wedstrijd toevoegen',
              onAction: () => context.go('/races/new'),
            );
          }
          final upcoming = list.where((r) => r.daysUntil >= 0).toList();
          final past = list.where((r) => r.daysUntil < 0).toList().reversed.toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              if (upcoming.isNotEmpty) ...[
                const _Header('Komend'),
                for (final r in upcoming) _RaceTile(race: r),
              ],
              if (past.isNotEmpty) ...[
                const _Header('Afgelopen'),
                for (final r in past) _RaceTile(race: r),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(color: RwColors.subtle, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
      );
}

class _RaceTile extends StatelessWidget {
  const _RaceTile({required this.race});
  final RaceEvent race;

  @override
  Widget build(BuildContext context) {
    final d = race.daysUntil;
    final when = d == 0
        ? 'Vandaag!'
        : d == 1
            ? 'Morgen'
            : d > 0
                ? 'Over $d dagen'
                : Fmt.date(race.raceDate);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RwCard(
        onTap: () => context.go('/races/${race.id}'),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(race.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    '${Fmt.date(race.raceDate)} · ${Fmt.km(race.distanceMeters, decimals: 1)} · doel ${Fmt.duration(race.goalTimeSeconds)}',
                    style: const TextStyle(color: RwColors.subtle),
                  ),
                ],
              ),
            ),
            Text(when,
                style: TextStyle(
                  color: d >= 0 ? RwColors.accent : RwColors.subtle,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }
}

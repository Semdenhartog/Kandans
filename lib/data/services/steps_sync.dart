import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n.dart';
import 'notification_service.dart';
import 'social_service.dart';
import 'sync_service.dart';

/// Houdt de stappenwedstrijd bij zonder dat je het scherm opent (punt 42):
/// bij het openen van de app (hooguit eens per 3 uur) je maandtotaal doorgeven, en een melding
/// als iemand uit je vriendenlijst je heeft ingehaald.
class StepsSync {
  StepsSync._();

  static const _lastKey = 'steps_sync_last';
  static const _rankKey = 'steps_last_rank';
  static const _aheadKey = 'steps_last_ahead';

  static Future<void> run(WidgetRef ref) async {
    try {
      final sync = ref.read(syncServiceProvider);
      if (!await sync.stepsEnabled()) return;
      final p = await SharedPreferences.getInstance();
      final last = DateTime.tryParse(p.getString(_lastKey) ?? '');
      if (last != null && DateTime.now().difference(last).inHours < 3) return;
      await p.setString(_lastKey, DateTime.now().toIso8601String());

      final now = DateTime.now();
      final steps = await sync.monthSteps(now);
      if (steps == null) return;
      final social = ref.read(socialServiceProvider);
      await social.submitSteps(now, steps);
      final board = await social.stepsBoard('friends', month: now);
      final me = board.where((e) => e.isMe).firstOrNull;
      if (me == null || board.length < 2) return;

      // Alleen in dezelfde maand vergelijken.
      final monthTag = '${now.year}-${now.month}';
      final prevRank = p.getString(_rankKey)?.split('|');
      final ahead = [for (final e in board) if (!e.isMe && e.rank < me.rank) e.nickname];
      final prevAhead = (p.getString(_aheadKey) ?? '').split('|').where((x) => x.isNotEmpty).toSet();
      await p.setString(_rankKey, '$monthTag|${me.rank}');
      await p.setString(_aheadKey, ahead.join('|'));
      if (prevRank == null || prevRank.first != monthTag) return;
      final newcomers = ahead.where((n) => !prevAhead.contains(n)).toList();
      if (newcomers.isEmpty) return;
      final who = newcomers.first;
      await NotificationService.instance.showSteps(
        trf('{naam} heeft je ingehaald', {'naam': who}),
        trf('Je staat nu {plek}e in de stappen van de maand. Een extra wandeling?', {'plek': me.rank}),
      );
    } catch (_) {
      // Geen internet of geen toestemming: volgende keer opnieuw.
    }
  }
}

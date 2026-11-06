import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n.dart';
import 'notification_service.dart';
import 'social_service.dart';

/// Haalt nieuwe @vermeldingen op (bij openen of terugkomen in de app, hooguit eens per 10 minuten)
/// en toont er één melding voor. Er is geen pushdienst; dit is de zuinige tussenweg.
class MentionSync {
  MentionSync._();

  static const _lastKey = 'mentions_last_check';

  static Future<void> run(WidgetRef ref, {bool force = false}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final last = DateTime.tryParse(p.getString(_lastKey) ?? '');
      if (!force && last != null && DateTime.now().difference(last).inMinutes < 10) return;
      await p.setString(_lastKey, DateTime.now().toIso8601String());
      final list = await ref.read(socialServiceProvider).newMentions();
      if (list.isEmpty) return;
      final first = list.first;
      final title = list.length == 1
          ? trf('{naam} noemde je in een reactie', {'naam': first.by})
          : trf('Je bent {n} keer genoemd in Samen', {'n': list.length});
      await NotificationService.instance.showMention(title, first.body);
    } catch (_) {
      // Niet ingelogd, geen Samen-lid of geen internet: later opnieuw.
    }
  }
}

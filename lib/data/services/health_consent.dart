import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/i18n.dart';
import '../../features/profile/privacy_screen.dart';

/// Uitdrukkelijke toestemming voor gezondheidsgegevens (AVG art. 9): hartslag, slaap, rusthartslag, HRV en pijntjes.
///
/// Wordt apart gevraagd op het moment dat iemand zo'n functie voor het eerst gebruikt, en is in te trekken via
/// Ik → Gezondheidsgegevens. Het moment van toestemming gaat ook mee in de accountgegevens (als bewijs), voor zover dat lukt.
class HealthConsent {
  HealthConsent._();

  static const _key = 'health_consent_v1';

  /// Is er toestemming gegeven?
  static Future<bool> granted() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _set(bool on) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, on);
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {
        'health_consent': on,
        'health_consent_at': DateTime.now().toUtc().toIso8601String(),
      }));
    } catch (_) {
      // Lukt dit niet (bijv. offline), dan geldt de keuze op dit toestel wel.
    }
  }

  /// Trekt de toestemming in. Er worden daarna geen nieuwe gezondheidsgegevens meer gelezen of bewaard.
  static Future<void> revoke() => _set(false);

  /// Vraagt toestemming als die er nog niet is. Geeft true als er (nu of eerder) toestemming is.
  static Future<bool> ensure(BuildContext context) async {
    if (await granted()) return true;
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Toestemming voor gezondheidsgegevens')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Voor deze functie gebruikt Kadans gezondheidsgegevens, zoals je hartslag, slaap, rusthartslag, HRV of pijntjes die je noteert.')),
            const SizedBox(height: 10),
            Text(tr('We gebruiken ze alleen voor jouw loopadvies en delen ze nooit met andere lopers. Je kunt je toestemming altijd intrekken via Ik → Gezondheidsgegevens.')),
            const SizedBox(height: 6),
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => openPrivacy(ctx),
              child: Text(tr('Lees de privacyverklaring')),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Niet nu'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Ik geef toestemming'))),
        ],
      ),
    );
    if (ok == true) {
      await _set(true);
      return true;
    }
    return false;
  }
}

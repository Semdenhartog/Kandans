import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stuurt onverwachte fouten naar de tabel `app_errors` in Supabase, zodat we
/// kunnen zien wat er bij testers misgaat. Geen persoonsgegevens behalve je
/// account-id; hooguit [maxPerSession] meldingen per keer dat de app open is.
class ErrorReporter {
  ErrorReporter._();

  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
  static const maxPerSession = 10;

  static int _sent = 0;
  static final _seen = <String>{};
  static bool _sending = false;

  /// Vangt fouten in Flutter (schermen) en in de rest van de app op.
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(details.exception, details.stack, context: details.context?.toDescription() ?? details.library);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, context: 'platform');
      return true;
    };
  }

  /// Korte, vaste sleutel om dezelfde fout niet steeds opnieuw te sturen.
  @visibleForTesting
  static String fingerprint(Object error, StackTrace? stack) {
    final firstFrame = (stack?.toString().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '') ?? '');
    return '${error.runtimeType}|${error.toString().split('\n').first}|$firstFrame';
  }

  @visibleForTesting
  static String clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

  static Future<void> report(Object error, StackTrace? stack, {String? context}) async {
    if (kDebugMode) debugPrint('RunWise-fout: $error\n$stack');
    if (_sending || _sent >= maxPerSession) return;
    final key = fingerprint(error, stack);
    if (!_seen.add(key)) return;
    SupabaseClient db;
    try {
      db = Supabase.instance.client;
    } catch (_) {
      return; // Supabase nog niet gestart.
    }
    if (db.auth.currentUser == null) return;
    _sending = true;
    _sent++;
    try {
      await db.from('app_errors').insert({
        'message': clip(error.toString(), 2000),
        'stack': stack == null ? null : clip(stack.toString(), 8000),
        'context': context == null ? null : clip(context, 200),
        'app_version': appVersion,
        'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      });
    } catch (_) {
      // Melden mag nooit zelf een fout geven.
    } finally {
      _sending = false;
    }
  }
}

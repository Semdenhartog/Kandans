import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';

/// Zet een wekker in de Klok-app van de telefoon (geen extra rechten of server nodig).
/// Geeft false terug als het niet lukt.
Future<bool> setAlarm(DateTime at, String message) async {
  if (!Platform.isAndroid) return false;
  try {
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: <String, dynamic>{
        'android.intent.extra.alarm.HOUR': at.hour,
        'android.intent.extra.alarm.MINUTES': at.minute,
        'android.intent.extra.alarm.MESSAGE': message,
        'android.intent.extra.alarm.SKIP_UI': false,
      },
    );
    await intent.launch();
    return true;
  } catch (_) {
    return false;
  }
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tijdens een run het opnamescherm (grote cijfers) boven het vergrendelscherm tonen (punt 52):
/// even op de aan/uit-knop drukken en je ziet tijd, afstand en tempo zonder te ontgrendelen.
/// Alleen zolang het opnamescherm open is en er opgenomen wordt; daarna gaat het meteen weer uit,
/// zodat de rest van de app achter je vergrendeling blijft.
class LockScreenDisplay {
  LockScreenDisplay._();

  static const _channel = MethodChannel('kadans/screen');
  static const _key = 'rec_lockscreen';
  static bool _shown = false;

  static Future<bool> enabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool on) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, on);
    } catch (_) {}
    if (!on) await show(false);
  }

  static Future<void> show(bool on) async {
    if (!Platform.isAndroid || _shown == on) return;
    try {
      await _channel.invokeMethod<bool>('showOnLock', {'on': on});
      _shown = on;
    } catch (_) {
      // Oudere build zonder dit kanaal: dan alleen de melding op het vergrendelscherm.
    }
  }
}

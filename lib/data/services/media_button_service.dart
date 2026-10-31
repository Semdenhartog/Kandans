import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De knop op je oortjes tijdens een run: één druk = pauze/verder, twee keer = ronde.
/// Werkt via een eigen Android-mediasessie (android_extra/kotlin/KadansChannels.kt).
/// Speelt er muziek, dan kan die app de knop overnemen.
class MediaButtonService {
  MediaButtonService._();
  static final instance = MediaButtonService._();

  static const _m = MethodChannel('kadans/media');
  static const _e = EventChannel('kadans/media/events');
  static const _key = 'earbuds_buttons';

  StreamSubscription<dynamic>? _sub;

  static Future<bool> enabled() async {
    if (!Platform.isAndroid) return false;
    final p = await SharedPreferences.getInstance();
    return p.getBool(_key) ?? false;
  }

  static Future<void> setEnabled(bool on) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, on);
  }

  /// [onToggle] bij één druk, [onLap] bij twee keer drukken of "volgende".
  Future<void> start({required void Function() onToggle, required void Function() onLap}) async {
    if (!await enabled()) return;
    try {
      await _sub?.cancel();
      _sub = _e.receiveBroadcastStream().listen((e) {
        if (e == 'toggle') onToggle();
        if (e == 'lap') onLap();
      }, onError: (Object _) {});
      await _m.invokeMethod<void>('start');
    } catch (_) {
      // Geen Android of kanaal ontbreekt: gewoon zonder knop.
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _m.invokeMethod<void>('stop');
    } catch (_) {}
  }
}

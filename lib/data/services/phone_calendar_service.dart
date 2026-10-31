import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/roster.dart';

/// Afspraken uit de telefoonagenda (Google, Samsung …) als drukke tijden.
/// Alleen begin- en eindtijd; titels worden niet gelezen en niets verlaat de telefoon.
class PhoneCalendarService {
  static const _channel = MethodChannel('kadans/calendar');
  static const _key = 'phone_calendar_on';

  static bool get supported => Platform.isAndroid;

  Future<bool> enabled() async {
    if (!supported) return false;
    final p = await SharedPreferences.getInstance();
    return p.getBool(_key) ?? false;
  }

  /// Zet aan (vraagt dan toestemming). Geeft false als de toestemming geweigerd is.
  Future<bool> setEnabled(bool on) async {
    final p = await SharedPreferences.getInstance();
    if (on) {
      final st = await Permission.calendarFullAccess.request();
      if (!st.isGranted) return false;
    }
    await p.setBool(_key, on);
    return true;
  }

  /// Drukke blokken voor de komende [days] dagen.
  Future<List<BusyBlock>> busy({int days = 8}) async {
    if (!await enabled()) return const [];
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(Duration(days: days));
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('busy', {
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
      });
      return [
        for (final m in raw ?? const <Map<Object?, Object?>>[])
          if (m['b'] is int && m['e'] is int)
            BusyBlock(
              DateTime.fromMillisecondsSinceEpoch(m['b'] as int),
              DateTime.fromMillisecondsSinceEpoch(m['e'] as int),
            ),
      ]..sort((a, b) => a.start.compareTo(b.start));
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}

final phoneCalendarServiceProvider = Provider((ref) => PhoneCalendarService());

final phoneCalendarOnProvider = FutureProvider<bool>((ref) => ref.read(phoneCalendarServiceProvider).enabled());

final phoneCalendarBusyProvider = FutureProvider<List<BusyBlock>>((ref) async {
  await ref.watch(phoneCalendarOnProvider.future);
  return ref.read(phoneCalendarServiceProvider).busy();
});

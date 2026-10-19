import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bewaart de laatst opgehaalde gegevens op de telefoon, zodat de app ook
/// zonder internet iets laat zien (runs, routes, profiel en het weer).
class OfflineCache {
  OfflineCache._();

  static const _prefix = 'offline_cache_';

  /// Sinds wanneer de app gegevens uit het geheugen toont (null = alles is vers).
  static final showingCachedSince = ValueNotifier<DateTime?>(null);

  static Future<void> save(String key, Object? data) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('$_prefix$key', jsonEncode({'at': DateTime.now().toIso8601String(), 'data': data}));
    } catch (_) {}
  }

  static Future<({Object? data, DateTime at})?> load(String key, {Duration? maxAge}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('$_prefix$key');
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.parse(m['at'] as String);
      if (maxAge != null && DateTime.now().difference(at) > maxAge) return null;
      return (data: m['data'], at: at);
    } catch (_) {
      return null;
    }
  }

  /// Wist alles (bij uitloggen of account verwijderen).
  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        await p.remove(k);
      }
    } catch (_) {}
    showingCachedSince.value = null;
  }

  /// Haalt vers op en bewaart; lukt dat niet, dan de bewaarde versie (als die er is).
  static Future<T> fetch<T>(
    String key,
    Future<T> Function() fresh, {
    required Object? Function(T value) encode,
    required T Function(Object? data) decode,
    Duration? maxAge,
  }) async {
    try {
      final v = await fresh();
      save(key, encode(v)).ignore();
      if (showingCachedSince.value != null) showingCachedSince.value = null;
      return v;
    } catch (e) {
      final cached = await load(key, maxAge: maxAge);
      if (cached == null) rethrow;
      final old = showingCachedSince.value;
      if (old == null || cached.at.isBefore(old)) showingCachedSince.value = cached.at;
      return decode(cached.data);
    }
  }
}

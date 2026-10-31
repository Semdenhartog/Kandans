import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/commute.dart';

const _key = 'commute_v1';

/// Instellingen voor rennend naar je werk (alleen op dit toestel).
final commuteSettingsProvider = FutureProvider<CommuteSettings>((ref) async {
  try {
    final p = await SharedPreferences.getInstance();
    return CommuteSettings.fromJson(jsonDecode(p.getString(_key) ?? '{}'));
  } catch (_) {
    return const CommuteSettings();
  }
});

Future<void> saveCommuteSettings(WidgetRef ref, CommuteSettings c) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_key, jsonEncode(c.toJson()));
  ref.invalidate(commuteSettingsProvider);
}

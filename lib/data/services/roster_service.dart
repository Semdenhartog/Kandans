import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/roster.dart';

/// Gekoppeld rooster: diensten en instellingen (op dit toestel bewaard).
class RosterState {
  const RosterState({this.url, this.shifts = const [], this.fetchedAt, this.options = const RosterOptions(), this.fromFile = false});

  /// Agenda-link (https of webcal); null bij een los bestand of geen rooster.
  final String? url;
  final List<BusyBlock> shifts;
  final DateTime? fetchedAt;
  final RosterOptions options;
  final bool fromFile;

  bool get linked => url != null || fromFile;

  /// Diensten die nog komen.
  List<BusyBlock> get upcoming => [for (final s in shifts) if (s.end.isAfter(DateTime.now())) s];

  List<BusyBlock> get blocks => blockedTimes(upcoming, options: options);
}

class RosterService {
  RosterService([http.Client? client]) : _http = client ?? http.Client();
  final http.Client _http;

  static const _kUrl = 'roster_url', _kShifts = 'roster_shifts', _kAt = 'roster_at', _kFile = 'roster_file';
  static const _kTravel = 'roster_travel', _kRest = 'roster_rest';

  Future<RosterState> load({bool refresh = true}) async {
    final p = await SharedPreferences.getInstance();
    final url = p.getString(_kUrl);
    var state = RosterState(
      url: url,
      fromFile: p.getBool(_kFile) ?? false,
      fetchedAt: DateTime.tryParse(p.getString(_kAt) ?? ''),
      shifts: _decode(p.getString(_kShifts)),
      options: RosterOptions(travelMinutes: p.getInt(_kTravel) ?? 30, restAfterNight: p.getBool(_kRest) ?? true),
    );
    // Een link elke 6 uur verversen (nieuwe of geruilde diensten). Mislukt het, dan de vorige versie.
    final stale = state.fetchedAt == null || DateTime.now().difference(state.fetchedAt!) > const Duration(hours: 6);
    if (refresh && url != null && stale) {
      try {
        state = await linkUrl(url);
      } catch (_) {}
    }
    return state;
  }

  /// Rooster koppelen via een agenda-link. Gooit een fout als de link niet werkt of geen diensten bevat.
  Future<RosterState> linkUrl(String raw) async {
    var url = raw.trim();
    if (url.startsWith('webcal://')) url = 'https://${url.substring(9)}';
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw Exception('Dit is geen geldige agenda-link. Hij begint meestal met https:// of webcal://.');
    }
    final res = await _http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('De agenda-link gaf een fout (${res.statusCode}).');
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (!body.contains('BEGIN:VCALENDAR')) throw Exception('Op deze link staat geen agenda (.ics).');
    final shifts = parseIcs(body);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, raw.trim());
    await p.setBool(_kFile, false);
    await _saveShifts(p, shifts);
    return load(refresh: false);
  }

  /// Rooster uit een los .ics-bestand (wordt niet vanzelf ververst).
  Future<RosterState> linkFile(String ics) async {
    if (!ics.contains('BEGIN:VCALENDAR')) throw Exception('Dit is geen agenda-bestand (.ics).');
    final shifts = parseIcs(ics);
    final p = await SharedPreferences.getInstance();
    await p.remove(_kUrl);
    await p.setBool(_kFile, true);
    await _saveShifts(p, shifts);
    return load(refresh: false);
  }

  Future<void> setOptions({int? travelMinutes, bool? restAfterNight}) async {
    final p = await SharedPreferences.getInstance();
    if (travelMinutes != null) await p.setInt(_kTravel, travelMinutes);
    if (restAfterNight != null) await p.setBool(_kRest, restAfterNight);
  }

  Future<void> unlink() async {
    final p = await SharedPreferences.getInstance();
    for (final k in [_kUrl, _kShifts, _kAt, _kFile]) {
      await p.remove(k);
    }
  }

  Future<void> _saveShifts(SharedPreferences p, List<BusyBlock> shifts) async {
    await p.setString(_kShifts, jsonEncode([for (final s in shifts) s.toJson()]));
    await p.setString(_kAt, DateTime.now().toIso8601String());
  }

  static List<BusyBlock> _decode(String? raw) {
    if (raw == null) return const [];
    try {
      return [
        for (final x in jsonDecode(raw) as List)
          if (BusyBlock.fromJson(x) case final b?) b,
      ];
    } catch (_) {
      return const [];
    }
  }
}

final rosterServiceProvider = Provider<RosterService>((ref) => RosterService());

final rosterProvider = FutureProvider<RosterState>((ref) async {
  try {
    return await ref.watch(rosterServiceProvider).load();
  } catch (_) {
    return const RosterState();
  }
});

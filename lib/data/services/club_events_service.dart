import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n.dart';
import '../../domain/club_calendar.dart';
import 'together_service.dart';

/// Een gekoppelde clubagenda (op dit toestel bewaard, niet op de server).
class ClubCalendarLink {
  const ClubCalendarLink(this.url, this.name);
  final String url;
  final String name;
  Map<String, dynamic> toJson() => {'u': url, 'n': name};
}

/// Clubevenementen: groepsruns uit je loopgroepen + gekoppelde clubagenda's.
class ClubEventsService {
  ClubEventsService([http.Client? client, TogetherService? together])
      : _http = client ?? http.Client(),
        _together = together ?? TogetherService();
  final http.Client _http;
  final TogetherService _together;

  static const maxLinks = 5;
  static const _kLinks = 'club_ical_links', _kCache = 'club_ical_cache', _kAt = 'club_ical_at';

  Future<List<ClubCalendarLink>> links() async {
    final p = await SharedPreferences.getInstance();
    try {
      final list = jsonDecode(p.getString(_kLinks) ?? '[]') as List;
      return [for (final m in list.cast<Map<String, dynamic>>()) ClubCalendarLink('${m['u']}', '${m['n']}')];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveLinks(List<ClubCalendarLink> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLinks, jsonEncode([for (final x in l) x.toJson()]));
    await p.remove(_kAt); // opnieuw ophalen
  }

  Future<String> _fetch(Uri uri) async {
    final res = await _http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('De agenda gaf foutcode ${res.statusCode}.');
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (!body.contains('BEGIN:VCALENDAR')) throw Exception('Deze link is geen agenda-link (iCal).');
    return body;
  }

  /// Koppelt een clubagenda. Gooit een fout als de link niet werkt. Geeft het aantal komende evenementen terug.
  Future<int> addLink(String raw) async {
    final uri = normalizeCalendarUrl(raw);
    if (uri == null) throw Exception('Dit is geen geldige link.');
    final current = await links();
    if (current.any((l) => l.url == uri.toString())) throw Exception('Deze agenda is al gekoppeld.');
    if (current.length >= maxLinks) throw Exception('Je kunt hooguit $maxLinks agenda\'s koppelen.');
    final body = await _fetch(uri);
    final name = icsCalendarName(body) ?? uri.host.replaceFirst('www.', '');
    final events = parseClubIcs(body, from: name);
    await _saveLinks([...current, ClubCalendarLink(uri.toString(), name)]);
    return events.length;
  }

  Future<void> removeLink(String url) async {
    await _saveLinks([for (final l in await links()) if (l.url != url) l]);
  }

  /// Evenementen uit de gekoppelde agenda's; elke 6 uur opnieuw opgehaald, anders uit de cache.
  Future<List<ClubEvent>> calendarEvents({bool force = false}) async {
    final p = await SharedPreferences.getInstance();
    final l = await links();
    if (l.isEmpty) return const [];
    final at = DateTime.tryParse(p.getString(_kAt) ?? '');
    final fresh = at != null && DateTime.now().difference(at) < const Duration(hours: 6);
    if (fresh && !force) return _cached(p);
    final all = <ClubEvent>[];
    var ok = false;
    for (final link in l) {
      final uri = normalizeCalendarUrl(link.url);
      if (uri == null) continue;
      try {
        all.addAll(parseClubIcs(await _fetch(uri), from: link.name));
        ok = true;
      } catch (_) {
        // Eén agenda niet bereikbaar: de rest gewoon tonen.
      }
    }
    if (!ok) return _cached(p);
    await p.setString(_kCache, jsonEncode([for (final e in all) e.toJson()]));
    await p.setString(_kAt, DateTime.now().toIso8601String());
    return all;
  }

  List<ClubEvent> _cached(SharedPreferences p) {
    try {
      final list = jsonDecode(p.getString(_kCache) ?? '[]') as List;
      return list.cast<Map<String, dynamic>>().map(ClubEvent.fromJson).whereType<ClubEvent>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Komende groepsruns uit al je loopgroepen (alleen als je meedoet met Samen).
  Future<(List<ClubEvent>, Map<int, RunGroup>)> groupEvents() async {
    final groups = await _together.groups();
    final byId = {for (final g in groups) g.id: g};
    final lists = await Future.wait([
      for (final g in groups.take(10))
        _together.groupRuns(g.id).then((runs) => [
              for (final r in runs)
                ClubEvent(
                  title: (r.note ?? '').trim().isNotEmpty ? r.note!.trim() : trf('Groepsrun {groep}', {'groep': g.name}),
                  start: r.startsAt,
                  end: r.startsAt.add(const Duration(hours: 1)),
                  source: ClubEventSource.group,
                  from: g.name,
                  location: r.place,
                  groupId: g.id,
                  going: r.going,
                  distanceKm: r.distanceKm,
                ),
            ]).catchError((_) => <ClubEvent>[]),
    ]);
    return (lists.expand((x) => x).toList(), byId);
  }
}

class ClubEventsState {
  const ClubEventsState(this.events, this.groups, this.links);
  final List<ClubEvent> events;
  final Map<int, RunGroup> groups;
  final List<ClubCalendarLink> links;
}

final clubEventsServiceProvider = Provider((ref) => ClubEventsService());

/// Alle komende clubevenementen. Fouten bij groepen (bijv. nog niet meedoen met Samen) worden overgeslagen.
final clubEventsProvider = FutureProvider<ClubEventsState>((ref) async {
  final svc = ref.read(clubEventsServiceProvider);
  final results = await Future.wait<Object?>([
    svc.groupEvents().then<Object?>((v) => v).catchError((_) => null),
    svc.calendarEvents().catchError((_) => const <ClubEvent>[]),
    svc.links(),
  ]);
  final g = results[0] as (List<ClubEvent>, Map<int, RunGroup>)?;
  final cal = results[1] as List<ClubEvent>;
  final links = results[2] as List<ClubCalendarLink>;
  return ClubEventsState(mergeClubEvents([g?.$1 ?? const [], cal]), g?.$2 ?? const {}, links);
});

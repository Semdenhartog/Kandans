// Clubevenementen: groepsruns uit je loopgroepen en items uit een gekoppelde clubagenda (iCal-link).
// Getoond als veegkaarten met een datumtegel in Samen (zie features/community/club_events_strip.dart).

import 'roster.dart' show parseIcsDate;

/// Waar een evenement vandaan komt.
enum ClubEventSource { group, calendar }

class ClubEvent {
  const ClubEvent({
    required this.title,
    required this.start,
    required this.source,
    required this.from,
    this.end,
    this.allDay = false,
    this.location,
    this.url,
    this.description,
    this.groupId,
    this.going,
    this.distanceKm,
  });

  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final ClubEventSource source;

  /// Naam van de loopgroep of de agenda ("SSS Barneveld").
  final String from;
  final String? location;
  final String? url;
  final String? description;

  /// Alleen bij groepsruns: de groep, het aantal aanmeldingen en de afstand.
  final int? groupId;
  final int? going;
  final double? distanceKm;

  /// Sleutel om dubbelingen te herkennen (zelfde titel op hetzelfde moment).
  String get key => '${title.toLowerCase()}|${start.toIso8601String()}';

  Map<String, dynamic> toJson() => {
        't': title,
        's': start.toIso8601String(),
        if (end != null) 'e': end!.toIso8601String(),
        if (allDay) 'a': true,
        'f': from,
        if (location != null) 'l': location,
        if (url != null) 'u': url,
        if (description != null) 'd': description,
      };

  static ClubEvent? fromJson(Map<String, dynamic> j) {
    final s = DateTime.tryParse('${j['s']}');
    if (s == null) return null;
    return ClubEvent(
      title: '${j['t'] ?? ''}',
      start: s,
      end: DateTime.tryParse('${j['e']}'),
      allDay: j['a'] == true,
      source: ClubEventSource.calendar,
      from: '${j['f'] ?? ''}',
      location: j['l'] as String?,
      url: j['u'] as String?,
      description: j['d'] as String?,
    );
  }
}

String _unescape(String v) =>
    v.replaceAll(r'\n', '\n').replaceAll(r'\N', '\n').replaceAll(r'\,', ',').replaceAll(r'\;', ';').replaceAll(r'\\', r'\').trim();

/// Naam van de agenda (X-WR-CALNAME), of null.
String? icsCalendarName(String ics) {
  final m = RegExp(r'^X-WR-CALNAME[^:]*:(.+)$', multiLine: true).firstMatch(ics.replaceAll('\r\n', '\n'));
  final name = m == null ? null : _unescape(m.group(1)!);
  return name == null || name.isEmpty ? null : name;
}

/// Leest evenementen uit een iCalendar-bestand: alles wat nog niet voorbij is en binnen [days] dagen begint.
/// Anders dan bij het werkrooster tellen hele-dag-items wél mee (wedstrijden staan vaak zo in een clubagenda).
List<ClubEvent> parseClubIcs(String ics, {required String from, DateTime? now, int days = 90, int max = 60}) {
  final n = now ?? DateTime.now();
  final until = n.add(Duration(days: days));
  final lines = ics.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\n[ \t]'), '').split('\n');
  final out = <ClubEvent>[];
  DateTime? start, end;
  String? summary, location, url, description, status;
  var allDay = false, inEvent = false;
  for (final raw in lines) {
    final line = raw.trimRight();
    if (line == 'BEGIN:VEVENT') {
      inEvent = true;
      start = end = null;
      summary = location = url = description = status = null;
      allDay = false;
    } else if (line == 'END:VEVENT' && inEvent) {
      inEvent = false;
      final s = start;
      if (s == null || summary == null || summary.isEmpty) continue;
      if (status == 'CANCELLED') continue;
      final e = end ?? (allDay ? s.add(const Duration(days: 1)) : s.add(const Duration(hours: 1)));
      if (!e.isAfter(n) || s.isAfter(until)) continue;
      out.add(ClubEvent(
        title: summary,
        start: s,
        end: e,
        allDay: allDay,
        source: ClubEventSource.calendar,
        from: from,
        location: location,
        url: url,
        description: description,
      ));
    } else if (inEvent) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final head = line.substring(0, colon).toUpperCase();
      final value = line.substring(colon + 1).trim();
      switch (head.split(';').first) {
        case 'DTSTART':
          allDay = !value.contains('T'); // "20261212" of VALUE=DATE: hele dag
          start = parseIcsDate(value);
        case 'DTEND':
          end = parseIcsDate(value);
        case 'SUMMARY':
          summary = _unescape(value);
        case 'LOCATION':
          location = _unescape(value);
          if (location.isEmpty) location = null;
        case 'URL':
          url = value.isEmpty ? null : value;
        case 'DESCRIPTION':
          description = _unescape(value);
          if (description.isEmpty) description = null;
        case 'STATUS':
          status = value.toUpperCase();
      }
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out.length > max ? out.sublist(0, max) : out;
}

/// Voegt bronnen samen: gesorteerd op begintijd, zonder dubbelingen en zonder wat al voorbij is.
List<ClubEvent> mergeClubEvents(Iterable<List<ClubEvent>> lists, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final seen = <String>{};
  final out = <ClubEvent>[];
  for (final list in lists) {
    for (final e in list) {
      final over = (e.end ?? e.start.add(const Duration(hours: 1))).isBefore(n);
      if (over || !seen.add(e.key)) continue;
      out.add(e);
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// Maakt een agenda-link bruikbaar: webcal:// wordt https://. Geeft null bij een ongeldige link.
Uri? normalizeCalendarUrl(String raw) {
  var url = raw.trim();
  if (url.startsWith('webcal://')) url = 'https://${url.substring(9)}';
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) return null;
  return uri;
}

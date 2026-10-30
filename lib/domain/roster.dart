// Werkrooster koppelen (wisseldiensten): diensten uit een agenda-bestand (.ics) of agenda-link halen,
// zodat Kadans nooit een loopmoment voorstelt tijdens je dienst, je reistijd of je slaap na een nachtdienst.

/// Een blok waarin je niet kunt lopen.
class BusyBlock {
  const BusyBlock(this.start, this.end, {this.label, this.rest = false});
  final DateTime start;
  final DateTime end;
  final String? label;

  /// Rust na een nachtdienst (geen dienst zelf).
  final bool rest;

  bool overlaps(DateTime s, DateTime e) => s.isBefore(end) && e.isAfter(start);

  Map<String, dynamic> toJson() => {
        's': start.toIso8601String(),
        'e': end.toIso8601String(),
        if (label != null) 'l': label,
      };

  static BusyBlock? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = DateTime.tryParse('${j['s']}'), e = DateTime.tryParse('${j['e']}');
    if (s == null || e == null || !e.isAfter(s)) return null;
    return BusyBlock(s, e, label: j['l'] as String?);
  }
}

/// Instellingen voor het rooster.
class RosterOptions {
  const RosterOptions({this.travelMinutes = 30, this.restAfterNight = true, this.restHours = 6});

  /// Reistijd vóór en na elke dienst.
  final int travelMinutes;

  /// Na een nachtdienst eerst slapen: geen loopmoment in de uren erna.
  final bool restAfterNight;
  final int restHours;
}

/// Woorden in de titel waarmee een agenda-item géén dienst is.
final _offDuty = RegExp(r'\b(vrij|verlof|vakantie|rust|rustdag|ziek|feestdag|off|free|holiday)\b', caseSensitive: false);

/// Leest diensten uit een iCalendar-bestand (.ics). Hele-dag-items en "vrij"/"verlof" tellen niet mee.
/// Alleen diensten die nog niet voorbij zijn en binnen [days] dagen beginnen.
List<BusyBlock> parseIcs(String ics, {DateTime? now, int days = 21}) {
  final n = now ?? DateTime.now();
  final until = n.add(Duration(days: days));
  // Regels die met een spatie of tab beginnen horen bij de vorige regel (RFC 5545 "folding").
  final lines = ics.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\n[ \t]'), '').split('\n');
  final out = <BusyBlock>[];
  DateTime? start, end;
  String? summary;
  var allDay = false, inEvent = false;
  for (final raw in lines) {
    final line = raw.trimRight();
    if (line == 'BEGIN:VEVENT') {
      inEvent = true;
      start = end = null;
      summary = null;
      allDay = false;
    } else if (line == 'END:VEVENT' && inEvent) {
      inEvent = false;
      final s = start, e = end ?? start?.add(const Duration(hours: 8));
      if (s == null || e == null || allDay || !e.isAfter(s)) continue;
      if (summary != null && _offDuty.hasMatch(summary)) continue;
      if (e.difference(s) > const Duration(hours: 16)) continue; // geen dienst, maar bijv. een meerdaags item
      if (!e.isAfter(n) || s.isAfter(until)) continue;
      out.add(BusyBlock(s, e, label: summary));
    } else if (inEvent) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final head = line.substring(0, colon).toUpperCase();
      final value = line.substring(colon + 1).trim();
      final name = head.split(';').first;
      if (name == 'DTSTART') {
        if (head.contains('VALUE=DATE') && !value.contains('T')) allDay = true;
        start = parseIcsDate(value);
      } else if (name == 'DTEND') {
        end = parseIcsDate(value);
      } else if (name == 'SUMMARY') {
        summary = value.replaceAll(r'\,', ',').replaceAll(r'\;', ';').replaceAll(r'\n', ' ');
      }
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// "20261101T070000Z" (UTC), "20261101T070000" (lokale tijd) of "20261101" (hele dag).
DateTime? parseIcsDate(String v) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$').firstMatch(v.trim());
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i) ?? '0');
  if (m.group(4) == null) return DateTime(g(1), g(2), g(3));
  if (m.group(7) == 'Z') return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6)).toLocal();
  return DateTime(g(1), g(2), g(3), g(4), g(5), g(6));
}

/// Is dit een nachtdienst? Eindigt 's ochtends vroeg na minstens 6 uur werk, of begint 's avonds laat.
bool isNightShift(BusyBlock b) {
  final h = b.end.difference(b.start).inMinutes / 60;
  final endsEarly = b.end.hour >= 4 && b.end.hour <= 10 && b.end.day != b.start.day;
  return (endsEarly && h >= 6) || (b.start.hour >= 21 && h >= 6);
}

/// Maakt van diensten de blokken waarin je niet kunt lopen: dienst + reistijd, en rust na een nachtdienst.
List<BusyBlock> blockedTimes(List<BusyBlock> shifts, {RosterOptions options = const RosterOptions()}) {
  final travel = Duration(minutes: options.travelMinutes);
  return [
    for (final s in shifts) ...[
      BusyBlock(s.start.subtract(travel), s.end.add(travel), label: s.label),
      if (options.restAfterNight && isNightShift(s))
        BusyBlock(s.end.add(travel), s.end.add(travel).add(Duration(hours: options.restHours)), label: 'Slapen na je nachtdienst', rest: true),
    ],
  ];
}

/// Korte omschrijving van de eerstvolgende dienst, bijv. "za 07:00–15:30 (Vroege dienst)".
String shiftLabel(BusyBlock b) {
  const days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
  String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final l = b.label == null || b.label!.isEmpty ? '' : ' (${b.label})';
  return '${days[b.start.weekday - 1]} ${b.start.day}/${b.start.month} ${hm(b.start)}–${hm(b.end)}$l';
}

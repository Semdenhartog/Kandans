import 'roster.dart';

/// Wanneer je kunt lopen: per dag van de week één of meer tijdvakken.
/// Leeg = altijd (05:00 tot 22:00, zoals de app standaard rekent).
class TimeWindow {
  const TimeWindow(this.startMinute, this.endMinute);

  /// Minuten sinds middernacht.
  final int startMinute;
  final int endMinute;

  int get length => endMinute - startMinute;

  static String fmt(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  String get label => '${fmt(startMinute)}–${fmt(endMinute)}';

  List<int> toJson() => [startMinute, endMinute];
}

class Availability {
  const Availability(this.days, {this.busy = const []});

  /// Sleutel = weekdag (1 = maandag … 7 = zondag). Ontbrekende dag of lege lijst = die dag niet.
  final Map<int, List<TimeWindow>> days;

  /// Vaste blokken waarin je niet kunt (diensten uit je rooster, reistijd, slapen na een nachtdienst).
  final List<BusyBlock> busy;

  static const always = Availability({});

  /// Geen eigen weektijden ingesteld (wel kan er een rooster zijn, zie [busy]).
  bool get isAlways => days.isEmpty;

  /// Helemaal geen beperking: geen weektijden en geen rooster.
  bool get unrestricted => days.isEmpty && busy.isEmpty;

  Availability withBusy(List<BusyBlock> b) => Availability(days, busy: b);

  static const dayNames = ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'];

  /// Mag een run die om [start] begint en [minutes] duurt?
  bool allows(DateTime start, int minutes) {
    if (busy.isNotEmpty) {
      final end = start.add(Duration(minutes: minutes));
      if (busy.any((b) => b.overlaps(start, end))) return false;
    }
    if (isAlways) return true;
    final windows = days[start.weekday] ?? const [];
    final s = start.hour * 60 + start.minute;
    final e = s + minutes;
    return windows.any((w) => s >= w.startMinute && e <= w.endMinute);
  }

  /// Eerste toegestane starttijd binnen het uur van [hour] (stappen van [step] minuten).
  DateTime? firstAllowedInHour(DateTime hour, int minutes, {int step = 15}) {
    for (var m = 0; m < 60; m += step) {
      final t = hour.add(Duration(minutes: m));
      if (allows(t, minutes)) return t;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        for (final e in days.entries) '${e.key}': [for (final w in e.value) w.toJson()],
      };

  static Availability fromJson(Object? json) {
    if (json is! Map) return always;
    final out = <int, List<TimeWindow>>{};
    for (final e in json.entries) {
      final day = int.tryParse('${e.key}');
      if (day == null || day < 1 || day > 7 || e.value is! List) continue;
      out[day] = [
        for (final w in e.value as List)
          if (w is List && w.length == 2 && w[0] is num && w[1] is num && (w[1] as num) > (w[0] as num))
            TimeWindow((w[0] as num).toInt(), (w[1] as num).toInt()),
      ];
    }
    return Availability(out);
  }

  /// Korte omschrijving, bijv. "werkdagen 17:00–21:00, weekend 08:00–12:00".
  String get summary {
    if (isAlways) return 'Elke dag tussen 05:00 en 22:00';
    final parts = <String>[];
    for (var d = 1; d <= 7; d++) {
      final w = days[d] ?? const [];
      parts.add('${dayNames[d - 1].substring(0, 2)} ${w.isEmpty ? '–' : w.map((x) => x.label).join(', ')}');
    }
    return parts.join(' · ');
  }

  /// Snelle keuzes.
  static Availability preset(String name) => switch (name) {
        'werk' => Availability({
            for (var d = 1; d <= 5; d++) d: const [TimeWindow(17 * 60, 21 * 60 + 30)],
            6: const [TimeWindow(7 * 60, 19 * 60)],
            7: const [TimeWindow(7 * 60, 19 * 60)],
          }),
        'avond' => Availability({for (var d = 1; d <= 7; d++) d: const [TimeWindow(17 * 60, 22 * 60)]}),
        'ochtend' => Availability({for (var d = 1; d <= 7; d++) d: const [TimeWindow(5 * 60, 10 * 60)]}),
        _ => always,
      };
}

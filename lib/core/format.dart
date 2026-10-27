import 'package:intl/intl.dart';

import 'i18n.dart';

/// Hulpfuncties om getallen en tijden leesbaar te tonen (Nederlands).
class Fmt {
  // Datums in de gekozen taal (de opmaak wordt per taal bewaard).
  static final _cache = <String, DateFormat>{};
  static DateFormat _f(String pattern) {
    final loc = LanguageController.instance.lang.intlLocale;
    return _cache.putIfAbsent('$loc|$pattern', () => DateFormat(pattern, loc));
  }

  static DateFormat get _date => _f('EEE d MMM');
  static DateFormat get _dateLong => _f('EEEE d MMMM yyyy');
  static DateFormat get _time => _f('HH:mm');

  static String date(DateTime d) => _date.format(d.toLocal());
  static String dateLong(DateTime d) => _dateLong.format(d.toLocal());
  static String time(DateTime d) => _time.format(d.toLocal());

  /// 5000 -> "5,00 km"
  static String km(num meters, {int decimals = 2}) =>
      '${(meters / 1000).toStringAsFixed(decimals).replaceAll('.', ',')} km';

  /// 330 -> "5:30 /km"
  static String pace(num secondsPerKm) {
    if (secondsPerKm <= 0 || secondsPerKm.isNaN || secondsPerKm.isInfinite) {
      return '–';
    }
    final total = secondsPerKm.round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')} /km';
  }

  /// 3725 -> "1:02:05", 605 -> "10:05"
  static String duration(num seconds) {
    final total = seconds.round().abs();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }

  /// +45 -> "+0:45", -20 -> "-0:20"
  static String signedDuration(num seconds) {
    final sign = seconds < 0 ? '-' : '+';
    return '$sign${duration(seconds)}';
  }

  static String temp(num? c) =>
      c == null ? '–' : '${c.round()}°C';

  static String wind(num? kmh) =>
      kmh == null ? '–' : '${kmh.round()} km/u';

  static String pct(num? p) => p == null ? '–' : '${p.round()}%';

  /// Parseert "5:30" naar 330 seconden. Geeft null bij ongeldige invoer.
  static int? parseMinSec(String input) {
    final parts = input.trim().split(':');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0]);
    final s = int.tryParse(parts[1]);
    if (m == null || s == null || s < 0 || s > 59 || m < 0) return null;
    return m * 60 + s;
  }

  /// Parseert "1:45:00" of "45:00" naar seconden.
  static int? parseDuration(String input) {
    final parts = input.trim().split(':');
    if (parts.length == 2) return parseMinSec(input);
    if (parts.length != 3) return null;
    final h = int.tryParse(parts[0]);
    final rest = parseMinSec('${parts[1]}:${parts[2]}');
    if (h == null || h < 0 || rest == null) return null;
    if (int.parse(parts[1]) > 59) return null;
    return h * 3600 + rest;
  }

  /// Leest een decimaal getal met komma of punt: "5,2" -> 5.2
  static double? parseDecimal(String input) =>
      double.tryParse(input.trim().replaceAll(',', '.'));

  /// Windrichting in graden naar kompasrichting.
  static String compass(num degrees) {
    const dirs = ['N', 'NO', 'O', 'ZO', 'Z', 'ZW', 'W', 'NW'];
    final i = (((degrees % 360) + 22.5) ~/ 45) % 8;
    return dirs[i];
  }
}

import 'dart:math' as math;

import '../data/models/models.dart';

/// Luchtkwaliteit en pollen op één moment (Open-Meteo / CAMS).
class AirQuality {
  const AirQuality({
    required this.time,
    this.europeanAqi,
    this.grass,
    this.birch,
    this.alder,
    this.mugwort,
    this.ragweed,
  });

  final DateTime time;

  /// Europese luchtkwaliteitsindex: 0–20 goed, 20–40 redelijk, 40–60 matig,
  /// 60–80 slecht, 80–100 zeer slecht, >100 extreem slecht.
  final double? europeanAqi;

  /// Pollen in korrels per m³.
  final double? grass;
  final double? birch;
  final double? alder;
  final double? mugwort;
  final double? ragweed;
}

enum WarningLevel { info, caution, danger }

class RunWarning {
  const RunWarning(this.level, this.title, this.text, {this.kind = ''});
  final WarningLevel level;
  final String title;
  final String text;

  /// Korte sleutel, handig voor tests en iconen: thunder, gusts, heat, ice, dark, air, pollen.
  final String kind;
}

/// Pollendrempels (korrels/m³) voor "veel" en "matig".
const _pollenLevels = {
  'graspollen': (moderate: 20.0, high: 50.0),
  'berkenpollen': (moderate: 10.0, high: 100.0),
  'elzenpollen': (moderate: 10.0, high: 100.0),
  'bijvoetpollen': (moderate: 10.0, high: 50.0),
  'ambrosiapollen': (moderate: 10.0, high: 50.0),
};

/// Weer gedurende je run (om de 15 minuten), uit de verwachting.
List<HourWeather> weatherDuring(Forecast f, DateTime start, int minutes) => [
      for (var m = 0; m <= minutes; m += 15)
        if (f.precise(start.add(Duration(minutes: m))) case final w?) w,
    ];

/// Wanneer het donker wordt (of licht), op basis van de dag/nacht-gegevens in de verwachting.
DateTime? nextDarkness(Forecast f, DateTime from) {
  final series = f.quarters.isNotEmpty ? f.quarters : f.hours;
  for (final w in series) {
    if (!w.time.isBefore(from) && !w.isDay) return w.time;
  }
  return null;
}

/// Waarschuwingen voor een run die om [start] begint en [minutes] duurt.
List<RunWarning> runWarnings(Forecast f, DateTime start, int minutes, {AirQuality? air}) {
  final during = weatherDuring(f, start, minutes);
  if (during.isEmpty) return const [];
  final out = <RunWarning>[];
  final end = start.add(Duration(minutes: minutes));

  // Onweer: niet gaan.
  if (during.any((w) => (w.weatherCode ?? 0) >= 95)) {
    out.add(const RunWarning(WarningLevel.danger, 'Onweer verwacht',
        'Ga niet lopen tijdens onweer, zeker niet in open veld of bos. Kies een ander moment.',
        kind: 'thunder'));
  }

  // Windstoten.
  final gust = during.map((w) => w.windGusts ?? w.windSpeed).reduce(math.max);
  if (gust >= 60) {
    out.add(RunWarning(WarningLevel.danger, 'Zware windstoten',
        'Windstoten tot ${gust.round()} km/u. Pas op voor vallende takken en blijf uit het bos.', kind: 'gusts'));
  } else if (gust >= 45) {
    out.add(RunWarning(WarningLevel.caution, 'Harde windstoten',
        'Windstoten tot ${gust.round()} km/u. Reken op een zwaardere run en pas op in het bos.', kind: 'gusts'));
  }

  // Warmte.
  final feels = during.map((w) => w.feelsLike ?? w.temperature).reduce(math.max);
  if (feels >= 25) {
    // Ongeveer 0,35% trager per graad boven 15 °C, bij 6:00/km.
    final slower = ((feels - 15) * 0.0035 * 360).round();
    out.add(RunWarning(
      feels >= 30 ? WarningLevel.danger : WarningLevel.caution,
      feels >= 30 ? 'Heet: pas op voor oververhitting' : 'Warm',
      'Gevoelstemperatuur tot ${feels.round()} °C. Loop ongeveer $slower s/km rustiger, neem drinken mee '
          'en stop bij duizeligheid of hoofdpijn.',
      kind: 'heat',
    ));
  }

  // Gladheid.
  final minTemp = during.map((w) => w.temperature).reduce(math.min);
  final wet = during.any((w) => (w.precipitation ?? 0) > 0.05);
  final snow = during.any((w) {
    final c = w.weatherCode ?? 0;
    return (c >= 71 && c <= 77) || c == 85 || c == 86;
  });
  final freezingRain = during.any((w) => w.weatherCode == 56 || w.weatherCode == 57 || w.weatherCode == 66 || w.weatherCode == 67);
  if (freezingRain || (minTemp <= 1 && (wet || snow))) {
    out.add(const RunWarning(WarningLevel.danger, 'Glad',
        'Kans op ijzel of sneeuw op de weg. Loop rustig, kies verlichte en gestrooide paden of loop binnen.',
        kind: 'ice'));
  } else if (minTemp <= 0) {
    out.add(const RunWarning(WarningLevel.caution, 'Kans op gladheid',
        'Het vriest. Bruggen, fietspaden en bladeren kunnen glad zijn.', kind: 'ice'));
  }

  // Donker.
  final dark = nextDarkness(f, start);
  if (!during.first.isDay) {
    out.add(const RunWarning(WarningLevel.info, 'Het is donker',
        'Draag reflecterende kleding en een lampje, en kies verlichte wegen.', kind: 'dark'));
  } else if (dark != null && dark.isBefore(end)) {
    final hh = '${dark.hour.toString().padLeft(2, '0')}:${dark.minute.toString().padLeft(2, '0')}';
    out.add(RunWarning(WarningLevel.info, 'Donker voor je terug bent',
        'Rond $hh wordt het donker. Neem een lampje mee of begin eerder.', kind: 'dark'));
  }

  // Luchtkwaliteit en pollen.
  if (air != null) {
    final aqi = air.europeanAqi;
    if (aqi != null && aqi >= 60) {
      out.add(RunWarning(
        aqi >= 80 ? WarningLevel.danger : WarningLevel.caution,
        aqi >= 80 ? 'Zeer slechte luchtkwaliteit' : 'Slechte luchtkwaliteit',
        'Luchtkwaliteitsindex ${aqi.round()}. Doe het rustig aan, vooral met astma of COPD, of loop later.',
        kind: 'air',
      ));
    }
    final pollen = {
      'graspollen': air.grass,
      'berkenpollen': air.birch,
      'elzenpollen': air.alder,
      'bijvoetpollen': air.mugwort,
      'ambrosiapollen': air.ragweed,
    };
    final high = [
      for (final e in pollen.entries)
        if ((e.value ?? 0) >= _pollenLevels[e.key]!.high) e.key,
    ];
    final moderate = [
      for (final e in pollen.entries)
        if ((e.value ?? 0) >= _pollenLevels[e.key]!.moderate && !high.contains(e.key)) e.key,
    ];
    if (high.isNotEmpty) {
      out.add(RunWarning(WarningLevel.caution, 'Veel ${high.join(' en ')}',
          'Last van hooikoorts? Loop liever na een regenbui of laat op de avond, en draag een zonnebril.',
          kind: 'pollen'));
    } else if (moderate.isNotEmpty) {
      out.add(RunWarning(WarningLevel.info, 'Wat ${moderate.join(' en ')}',
          'Met hooikoorts kun je er last van hebben.', kind: 'pollen'));
    }
  }

  out.sort((a, b) => b.level.index.compareTo(a.level.index));
  return out;
}

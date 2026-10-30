import 'dart:math' as math;

import '../data/models/models.dart';
import 'sun_position.dart';

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

/// Hooikoorts-instelling (Ik → Pollen): bepaalt of en hoe pollen meetellen in de waarschuwingen.
enum PollenSensitivity {
  none('Geen hooikoorts', 'Geen pollenmeldingen'),
  normal('Normaal', 'Een melding bij veel pollen'),
  hayfever('Ik heb hooikoorts', 'Ook bij matige pollen een waarschuwing, met tips');

  const PollenSensitivity(this.label, this.explanation);
  final String label;
  final String explanation;
}

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
///
/// [pollen]: hoe zwaar pollen meetellen. [recentMaxTemp]: de warmste run van de afgelopen weken (°C), om de
/// eerste warme dag te herkennen. [hasRoute]: je volgt een route (dan staat de wind al in de routekaart).
List<RunWarning> runWarnings(
  Forecast f,
  DateTime start,
  int minutes, {
  AirQuality? air,
  PollenSensitivity pollen = PollenSensitivity.normal,
  double? recentMaxTemp,
  bool hasRoute = false,
  List<({double bearing, double meters, double startKm})> route = const [],
}) {
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
  final coolest = feels >= 25 ? _coolestDaylight(f, start) : null;
  final coolerText = coolest != null && (coolest.feelsLike ?? coolest.temperature) <= feels - 4
      ? ' Om ${_hhmm(coolest.time)} is het ${(coolest.feelsLike ?? coolest.temperature).round()} °C.'
      : '';
  if (feels >= 25) {
    // Ongeveer 0,35% trager per graad boven 15 °C, bij 6:00/km.
    final slower = ((feels - 15) * 0.0035 * 360).round();
    out.add(RunWarning(
      feels >= 30 ? WarningLevel.danger : WarningLevel.caution,
      feels >= 30 ? 'Heet: pas op voor oververhitting' : 'Warm',
      'Gevoelstemperatuur tot ${feels.round()} °C. Loop ongeveer $slower s/km rustiger, neem drinken mee '
          'en stop bij duizeligheid of hoofdpijn.$coolerText',
      kind: 'heat',
    ));
  }
  // Eerste warme dag: je lichaam is nog niet gewend aan warmte (dat duurt 1–2 weken).
  if (feels >= 22 && recentMaxTemp != null && recentMaxTemp < feels - 6) {
    out.add(RunWarning(WarningLevel.caution, 'Eerste warme dag',
        'Je liep de afgelopen weken bij hooguit ${recentMaxTemp.round()} °C. Je lichaam moet nog wennen aan warmte: '
            'begin rustig en drink extra.',
        kind: 'acclimatise'));
  }
  // Benauwd: warm en vochtig, zweet verdampt slecht.
  final muggy = during.any((w) => w.temperature >= 20 && (w.humidity ?? 0) >= 75);
  if (muggy && feels < 30) {
    out.add(const RunWarning(WarningLevel.info, 'Benauwd',
        'Warm en vochtig: je zweet verdampt slecht. Loop wat rustiger dan je gevoel zegt.', kind: 'muggy'));
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

  // Kou: warming-up binnen en gure wind.
  final coldFeels = during.map((w) => w.feelsLike ?? w.temperature).reduce(math.min);
  if (coldFeels <= -3) {
    out.add(RunWarning(WarningLevel.info, 'Koud',
        'Voelt als ${coldFeels.round()} °C. Doe je warming-up binnen en begin rustig: koude lucht prikt in je longen.',
        kind: 'cold'));
  } else if (minTemp <= 8 && during.any((w) => (w.feelsLike ?? w.temperature) <= w.temperature - 5)) {
    out.add(RunWarning(WarningLevel.info, 'Gure wind',
        'Door de wind voelt het als ${coldFeels.round()} °C. Bescherm je handen en oren.', kind: 'windchill'));
  }

  // Mist: slecht zicht.
  if (during.any((w) => w.weatherCode == 45 || w.weatherCode == 48)) {
    out.add(const RunWarning(WarningLevel.caution, 'Mist',
        'Slecht zicht: draag felle kleuren en een lampje, en pas op bij oversteken.', kind: 'fog'));
  }

  // Herfst: natte bladeren zijn glad.
  if ((start.month == 10 || start.month == 11) && minTemp > 1 &&
      during.any((w) => (w.precipitation ?? 0) > 0.05 || (w.precipitationProbability ?? 0) >= 60)) {
    out.add(const RunWarning(WarningLevel.info, 'Natte bladeren',
        'Op fietspaden en in het bos zijn natte bladeren glad, vooral in bochten.', kind: 'leaves'));
  }

  // Twijfelachtige bui: modellen geven een middelgrote kans zonder echte regen.
  final dry = during.every((w) => (w.precipitation ?? 0) < 0.1);
  final maybe = during.map((w) => w.precipitationProbability ?? 0).fold<double>(0, math.max);
  if (dry && maybe >= 30 && maybe < 60) {
    out.add(RunWarning(WarningLevel.info, 'Misschien een bui',
        'Kans op regen ${maybe.round()}%: het is onzeker. Een dun jack is genoeg.', kind: 'rainmaybe'));
  }

  // Wind op een rondje zonder route: begin tegen de wind in.
  final wind = during.map((w) => w.windSpeed).reduce(math.max);
  if (!hasRoute && wind >= 20 && gust < 45) {
    final dir = during.first.windDirection;
    final from = dir == null ? '' : ' (wind uit het ${_compass(dir)})';
    out.add(RunWarning(WarningLevel.info, 'Begin tegen de wind in',
        'Stevige wind$from: loop eerst tegen de wind in, dan heb je hem op de terugweg mee als je moe bent.',
        kind: 'windtip'));
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
    final counts = {
      'graspollen': air.grass,
      'berkenpollen': air.birch,
      'elzenpollen': air.alder,
      'bijvoetpollen': air.mugwort,
      'ambrosiapollen': air.ragweed,
    };
    final high = [
      for (final e in counts.entries)
        if ((e.value ?? 0) >= _pollenLevels[e.key]!.high) e.key,
    ];
    final moderate = [
      for (final e in counts.entries)
        if ((e.value ?? 0) >= _pollenLevels[e.key]!.moderate && !high.contains(e.key)) e.key,
    ];
    if (pollen == PollenSensitivity.none) {
      // Geen hooikoorts: geen pollenmeldingen.
    } else if (high.isNotEmpty) {
      out.add(RunWarning(
          pollen == PollenSensitivity.hayfever ? WarningLevel.danger : WarningLevel.caution,
          'Veel ${high.join(' en ')}',
          pollen == PollenSensitivity.hayfever
              ? 'Kies liever een ander moment: na een regenbui of laat op de avond. Zonnebril op en douche na je run.'
              : 'Last van hooikoorts? Loop liever na een regenbui of laat op de avond, en draag een zonnebril.',
          kind: 'pollen'));
    } else if (moderate.isNotEmpty) {
      out.add(RunWarning(
          pollen == PollenSensitivity.hayfever ? WarningLevel.caution : WarningLevel.info,
          'Wat ${moderate.join(' en ')}',
          pollen == PollenSensitivity.hayfever
              ? 'Je kunt er last van hebben: zonnebril op en neem je medicijnen op tijd.'
              : 'Met hooikoorts kun je er last van hebben.',
          kind: 'pollen'));
    }
  }

  out.sort((a, b) => b.level.index.compareTo(a.level.index));
  // Lage zon recht in je gezicht (alleen bij zon, niet bij bewolking): jij en automobilisten zien slecht.
  final low = <({DateTime time, double azimuth})>[];
  for (final w in during) {
    if (!w.isDay || (w.weatherCode != null && w.weatherCode! > 2)) continue;
    final sp = sunPosition(w.time, f.latitude, f.longitude);
    if (isLowSun(sp.elevation)) low.add((time: w.time, azimuth: sp.azimuth));
  }
  if (low.isNotEmpty) {
    final az = low[low.length ~/ 2].azimuth;
    final where = _compass(az);
    if (route.isNotEmpty) {
      final toward = fractionTowardSun(route, az);
      final reversed = fractionTowardSun([for (final s in route) (bearing: (s.bearing + 180) % 360, meters: s.meters, startKm: s.startKm)], az);
      if (toward >= 0.2) {
        final tip = reversed < toward - 0.15
            ? ' Loop je rondje andersom: dan heb je de zon ${reversed < 0.05 ? 'bijna nergens' : 'veel minder'} in je gezicht.'
            : ' Neem een pet of zonnebril mee.';
        out.add(RunWarning(WarningLevel.caution, 'Lage zon in je gezicht',
            '${(toward * 100).round()}% van je route loop je recht tegen de lage zon in (uit het $where). '
                'Automobilisten zien je dan slecht.$tip',
            kind: 'sun'));
      }
    } else {
      out.add(RunWarning(WarningLevel.info, 'Lage zon',
          'De zon staat laag in het $where. Loop je die kant op, dan zie je slecht en zien automobilisten jou slecht. '
              'Een pet of zonnebril helpt; kies liefst een rondje met de zon in je rug.',
          kind: 'sun'));
    }
  }

  return out;
}

/// Koelste uur bij daglicht in de komende 18 uur (voor het tip bij hitte).
HourWeather? _coolestDaylight(Forecast f, DateTime from) {
  HourWeather? best;
  for (final w in f.hours) {
    if (w.time.isBefore(from) || w.time.isAfter(from.add(const Duration(hours: 18))) || !w.isDay) continue;
    final t = w.feelsLike ?? w.temperature;
    if (best == null || t < (best.feelsLike ?? best.temperature)) best = w;
  }
  return best;
}

String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Windrichting in woorden ("zuidwesten").
String _compass(double deg) {
  const names = ['noorden', 'noordoosten', 'oosten', 'zuidoosten', 'zuiden', 'zuidwesten', 'westen', 'noordwesten'];
  return names[((deg % 360) / 45).round() % 8];
}

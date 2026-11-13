import 'custom_plan.dart';

/// Eén beurt van de coach in het schema-gesprek: een vraag met tikbare keuzes.
class PlanChatTurn {
  const PlanChatTurn(this.text, [this.options = const []]);
  final String text;
  final List<String> options;
}

enum PlanChatStep { goal, race, weekly, longest, days, ambition, fiveK, done }

/// Bouwt in het coachgesprek een schema op, vraag voor vraag (zonder AI, alles op het toestel).
///
/// Gebruik: [start] geeft de eerste vraag, [answer] verwerkt een antwoord en geeft de volgende vraag
/// (of dezelfde vraag met uitleg als het antwoord niet begrepen is). Bij [done] staan de wensen in [wishes].
class PlanChat {
  PlanChat({required this.now, double? weeklyKm, double? longestKm})
      : wishes = PlanWishes(weeklyKm: weeklyKm ?? 10, longestKm: longestKm ?? 5),
        _knownWeekly = weeklyKm,
        _knownLongest = longestKm;

  final DateTime now;
  PlanWishes wishes;
  PlanChatStep step = PlanChatStep.goal;

  /// Wat Kadans al uit het logboek weet (dan wordt die vraag overgeslagen).
  final double? _knownWeekly;
  final double? _knownLongest;

  bool get done => step == PlanChatStep.done;

  /// Vraagt de loper om een schema te maken (dan start het gesprek)?
  static bool wantsPlan(String text) {
    final t = text.toLowerCase();
    if (!RegExp(r'schema|trainingsplan|trainingsprogramma').hasMatch(t)) return false;
    return RegExp(r'\b(maak|maken|bouw|bouwen|stel|opstellen|samenstellen|geef|schrijf|nieuw|wil|graag|help|start|begin)\b').hasMatch(t);
  }

  static bool isStop(String text) =>
      RegExp(r'^(stop|stoppen|annuleer|annuleren|laat maar|afbreken|cancel)[\s.!]*$', caseSensitive: false).hasMatch(text.trim());

  PlanChatTurn start() => PlanChatTurn(
        'Leuk, we bouwen je schema. Ik stel je een paar korte vragen. Typ "stop" als je wilt ophouden.\n\n${_question().text}',
        _question().options,
      );

  /// Verwerkt het antwoord op de huidige vraag en geeft de volgende vraag. Bij [done] is de tekst leeg.
  PlanChatTurn answer(String text) {
    final t = text.trim().toLowerCase();
    final problem = _apply(t);
    if (problem != null) return PlanChatTurn('$problem\n\n${_question().text}', _question().options);
    step = _next(step);
    return done ? const PlanChatTurn('') : _question();
  }

  // ------------------------------------------------------------ de vragen

  PlanChatTurn _question() {
    switch (step) {
      case PlanChatStep.goal:
        return PlanChatTurn('Wat is je doel?', [for (final g in PlanGoal.values) g.label]);
      case PlanChatStep.race:
        return PlanChatTurn(
          'Wanneer is je ${wishes.goal.label.toLowerCase()}? Kies een keuze of typ een datum, bijvoorbeeld 14-3-${now.year + 1}.',
          const ['Over 8 weken', 'Over 12 weken', 'Over 16 weken', 'Nog geen datum'],
        );
      case PlanChatStep.weekly:
        return const PlanChatTurn(
          'Hoeveel kilometer loop je nu ongeveer per week?',
          ['0 tot 5 km', '5 tot 15 km', '15 tot 30 km', '30 tot 50 km', 'Meer dan 50 km'],
        );
      case PlanChatStep.longest:
        return const PlanChatTurn(
          'Wat was je langste run van de laatste weken?',
          ['3 km', '5 km', '8 km', '12 km', '16 km', '21 km of meer'],
        );
      case PlanChatStep.days:
        return const PlanChatTurn(
          'Op welke dagen wil je lopen? Kies een keuze of typ je dagen, bijvoorbeeld "ma wo za".',
          ['di do zo', 'ma wo za', 'di do za zo', 'ma wo vr zo', 'ma di do za zo'],
        );
      case PlanChatStep.ambition:
        return PlanChatTurn('Hoe ambitieus wil je trainen?', [for (final a in Ambition.values) '${a.label}: ${a.subtitle.toLowerCase()}']);
      case PlanChatStep.fiveK:
        return const PlanChatTurn(
          'Weet je een recente tijd op de 5 km? Typ hem als minuten:seconden, bijvoorbeeld 27:30. Dan kloppen je tempo\'s beter.',
          ['Weet ik niet'],
        );
      case PlanChatStep.done:
        return const PlanChatTurn('');
    }
  }

  PlanChatStep _next(PlanChatStep from) {
    var s = from;
    while (s != PlanChatStep.done) {
      s = PlanChatStep.values[s.index + 1];
      if (!_skip(s)) break;
    }
    return s;
  }

  bool _skip(PlanChatStep s) {
    final g = wishes.goal;
    return switch (s) {
      PlanChatStep.race => !g.isRace,
      PlanChatStep.weekly => g == PlanGoal.beginnen || _knownWeekly != null,
      PlanChatStep.longest => g == PlanGoal.beginnen || _knownLongest != null,
      PlanChatStep.ambition => g.isStarter,
      PlanChatStep.fiveK => g.isStarter || g == PlanGoal.fit,
      _ => false,
    };
  }

  // -------------------------------------------------- antwoorden begrijpen

  /// Verwerkt het antwoord; geeft een uitleg terug als het niet begrepen is.
  String? _apply(String t) {
    switch (step) {
      case PlanChatStep.goal:
        final g = parseGoal(t);
        if (g == null) return 'Dat doel herken ik niet.';
        wishes = wishes.copyWith(goal: g, weeks: g.defaultWeeks, clearRace: true);
        return null;
      case PlanChatStep.race:
        final d = parseRaceDate(t, now, wishes.goal.defaultWeeks);
        if (d == null) return 'Die datum begrijp ik niet.';
        final days = d.difference(DateTime(now.year, now.month, now.day)).inDays;
        if (days < 14) return 'Die datum is te dichtbij voor een schema. Kies een datum minstens twee weken vooruit.';
        if (days > 365) return 'Die datum ligt meer dan een jaar vooruit. Kies een datum binnen een jaar.';
        wishes = wishes.copyWith(raceDate: d);
        return null;
      case PlanChatStep.weekly:
        final n = parseKm(t);
        if (n == null || n > 250) return 'Typ een aantal kilometers, bijvoorbeeld 20.';
        wishes = wishes.copyWith(weeklyKm: n);
        return null;
      case PlanChatStep.longest:
        final n = parseKm(t);
        if (n == null || n > 100) return 'Typ een aantal kilometers, bijvoorbeeld 8.';
        wishes = wishes.copyWith(longestKm: n);
        return null;
      case PlanChatStep.days:
        final days = parseDays(t);
        if (days.length < 2) return 'Kies minstens twee dagen, bijvoorbeeld "di do zo".';
        if (days.length > 6) return 'Houd minstens één rustdag per week. Kies hooguit zes dagen.';
        final long = days.contains(7) ? 7 : (days.contains(6) ? 6 : days.last);
        wishes = wishes.copyWith(runDays: days, longRunDay: long);
        return null;
      case PlanChatStep.ambition:
        final a = Ambition.values.where((a) => t.startsWith(a.label.toLowerCase()) || t.contains(a.name)).firstOrNull;
        if (a == null) return 'Kies rustig, gebalanceerd of ambitieus.';
        wishes = wishes.copyWith(ambition: a);
        return null;
      case PlanChatStep.fiveK:
        if (RegExp(r'weet|geen|nee|niet|sla over|skip').hasMatch(t)) {
          wishes = wishes.copyWith(clear5k: true);
          return null;
        }
        final s = parseFiveK(t);
        if (s == null) return 'Typ je tijd als minuten:seconden, bijvoorbeeld 27:30, of kies "Weet ik niet".';
        wishes = wishes.copyWith(recent5kSeconds: s);
        return null;
      case PlanChatStep.done:
        return null;
    }
  }

  static PlanGoal? parseGoal(String t) {
    for (final g in PlanGoal.values) {
      if (t == g.label.toLowerCase()) return g;
    }
    if (t.contains('halve') || RegExp(r'\b21\b').hasMatch(t)) return PlanGoal.halve;
    if (t.contains('marathon') || RegExp(r'\b42\b').hasMatch(t)) return PlanGoal.marathon;
    if (RegExp(r'\b(15|16)\b').hasMatch(t) || t.contains('mijl')) return PlanGoal.k15;
    if (RegExp(r'\b10\b').hasMatch(t)) return PlanGoal.k10;
    if (RegExp(r'\b5\b').hasMatch(t)) return PlanGoal.k5;
    if (t.contains('terug') || t.contains('blessure') || t.contains('pauze')) return PlanGoal.terugkomen;
    if (t.contains('begin') || t.contains('start')) return PlanGoal.beginnen;
    if (t.contains('snel')) return PlanGoal.sneller;
    if (t.contains('fit') || t.contains('conditie')) return PlanGoal.fit;
    return null;
  }

  static const _months = ['jan', 'feb', 'maa', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];

  /// "over 12 weken", "14-3-2027", "14-3", "14 maart" of "nog geen datum" (dan de gebruikelijke duur voor dit doel).
  static DateTime? parseRaceDate(String t, DateTime now, int defaultWeeks) {
    final today = DateTime(now.year, now.month, now.day);
    // Dagen optellen via de kalender (niet via uren), zodat zomer- en wintertijd de datum niet verschuiven.
    DateTime plus(int days) => DateTime(today.year, today.month, today.day + days);
    final weeks = RegExp(r'(\d{1,2})\s*(weken|week|wk)').firstMatch(t);
    if (weeks != null) return plus(int.parse(weeks.group(1)!) * 7);
    final months = RegExp(r'(\d{1,2})\s*(maanden|maand)').firstMatch(t);
    if (months != null) return plus(int.parse(months.group(1)!) * 30);
    if (RegExp(r'geen|weet|maakt niet uit').hasMatch(t)) return plus(defaultWeeks * 7);
    DateTime? make(int d, int m, int? y) {
      if (d < 1 || d > 31 || m < 1 || m > 12) return null;
      var year = y ?? now.year;
      if (year < 100) year += 2000;
      var date = DateTime(year, m, d);
      if (date.month != m) return null;
      if (y == null && date.isBefore(today)) date = DateTime(year + 1, m, d);
      return date;
    }

    final digits = RegExp(r'(\d{1,2})[-/. ](\d{1,2})(?:[-/. ](\d{2,4}))?').firstMatch(t);
    if (digits != null) {
      return make(int.parse(digits.group(1)!), int.parse(digits.group(2)!), digits.group(3) == null ? null : int.parse(digits.group(3)!));
    }
    final word = RegExp(r'(\d{1,2})\s+([a-z]{3})[a-z]*(?:\s+(\d{4}))?').firstMatch(t);
    if (word != null) {
      final m = _months.indexOf(word.group(2)! == 'mrt' ? 'maa' : word.group(2)!);
      if (m >= 0) return make(int.parse(word.group(1)!), m + 1, word.group(3) == null ? null : int.parse(word.group(3)!));
    }
    return null;
  }

  /// "15 tot 30 km" → 22,5; "meer dan 50" → 55; "8 km" → 8; "21 km of meer" → 21.
  static double? parseKm(String t) {
    final nums = [for (final m in RegExp(r'\d+(?:[.,]\d+)?').allMatches(t)) double.parse(m.group(0)!.replaceAll(',', '.'))];
    if (nums.isEmpty) return RegExp(r'niets|nul|niet').hasMatch(t) ? 0.0 : null;
    if (nums.length >= 2 && RegExp(r'tot|-|–').hasMatch(t)) return (nums[0] + nums[1]) / 2;
    if (t.contains('meer dan')) return nums.first * 1.1;
    return nums.first;
  }

  static const _dayNames = {'ma': 1, 'di': 2, 'wo': 3, 'do': 4, 'vr': 5, 'za': 6, 'zo': 7};

  /// "ma wo za", "maandag, woensdag en zaterdag" → [1, 3, 6].
  static List<int> parseDays(String t) {
    final out = <int>{};
    for (final w in RegExp(r'[a-z]+').allMatches(t)) {
      final word = w.group(0)!;
      if (word.length < 2) continue;
      final d = _dayNames[word.substring(0, 2)];
      if (d != null && (word.length == 2 || word.endsWith('dag'))) out.add(d);
    }
    return out.toList()..sort();
  }

  /// "27:30" → 1650; "27" → 1620 (minuten). Alleen tijden tussen 12 en 70 minuten.
  static int? parseFiveK(String t) {
    final ms = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(t);
    int? s;
    if (ms != null) {
      final sec = int.parse(ms.group(2)!);
      if (sec > 59) return null;
      s = int.parse(ms.group(1)!) * 60 + sec;
    } else {
      final m = RegExp(r'\b(\d{2})\b').firstMatch(t);
      if (m != null) s = int.parse(m.group(1)!) * 60;
    }
    if (s == null || s < 12 * 60 || s > 70 * 60) return null;
    return s;
  }
}

const _weekdays = ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'];

String _kmText(double km) => km.toStringAsFixed(km.roundToDouble() == km ? 0 : 1).replaceAll('.', ',');

/// Korte samenvatting van het schema voor in het gesprek.
String planChatSummary(CustomPlan plan) {
  final w = plan.wishes;
  final days = [for (final d in w.runDays) _weekdays[d - 1]].join(', ');
  final lines = <String>[
    'Je schema is klaar: ${w.goal.label}, ${plan.weeks.length} weken.',
    '- Loopdagen: $days',
    '- Zwaarste week: ${_kmText(plan.peakKm)} km',
  ];
  final race = plan.raceDate;
  if (race != null) lines.add('- Wedstrijd: ${race.day}-${race.month}-${race.year}');
  if (plan.predictedSeconds != null && w.goal.isRace) {
    lines.add('- Verwachte eindtijd: ongeveer ${fmtTime(plan.predictedSeconds!)}${plan.paceIsEstimate ? ' (schatting)' : ''}');
  }
  final first = plan.weeks.where((x) => x.items.isNotEmpty).firstOrNull;
  if (first != null) {
    lines.add('');
    lines.add('Je eerste week:');
    for (final i in first.items) {
      lines.add('- ${_weekdays[i.session.date.weekday - 1]}: ${i.session.title}');
    }
  }
  for (final warning in plan.warnings.take(2)) {
    lines.add('');
    lines.add('Let op: $warning');
  }
  lines.add('');
  lines.add('Bekijk het hele schema met tempo\'s en uitleg, of zet het meteen in je plan.');
  return lines.join('\n');
}

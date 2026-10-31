import '../data/models/models.dart';

// Pijntjes-dagboek: plek en ernst bij het label "Pijntje" (in de notitie van de run, zo staat het overal),
// en patronen herkennen: hoe vaak, en bij welke runs (lang, snel, veel opgebouwd, bepaalde schoen).
// Geen diagnose: wel een seintje om op tijd rustiger aan te doen of naar een fysio te gaan.

enum PainSpot {
  shin('scheen'),
  knee('knie'),
  calf('kuit'),
  achilles('achilles'),
  foot('voet'),
  hip('heup'),
  hamstring('hamstring'),
  back('rug');

  const PainSpot(this.label);
  final String label;

  String get advice => switch (this) {
        PainSpot.shin => 'Scheenpijn komt vaak door te snel opbouwen of veel harde ondergrond. Loop een paar keer op gras of bospad en houd de kilometers even gelijk.',
        PainSpot.knee => 'Knieklachten hebben vaak te maken met heup- en bilspieren of te lange passen. Iets kortere, snellere passen helpen vaak.',
        PainSpot.calf => 'Kuitklachten: rustig opwarmen, niet meteen hard heuvel op, en kuitheffingen als oefening.',
        PainSpot.achilles => 'Achillespees: ga er niet doorheen lopen. Liever een paar dagen rust en langzame kuitoefeningen.',
        PainSpot.foot => 'Voetpijn: kijk naar je schoenen (versleten of te krap) en bouw kale-voet-tijd rustig op.',
        PainSpot.hip => 'Heupklachten: vaak zwakke bilspieren. Krachtoefeningen voor je heupen en billen helpen.',
        PainSpot.hamstring => 'Hamstring: geen sprints of snelle intervallen tot het rustig voelt.',
        PainSpot.back => 'Rugpijn: een sterke romp helpt. Let ook op je houding als je moe wordt.',
      };
}

class PainEntry {
  const PainEntry(this.run, this.spot, this.severity);
  final Activity run;
  final PainSpot spot;

  /// 1 (licht) tot 10 (heel erg).
  final int severity;
}

final _re = RegExp(r'Pijntje:\s*([a-z]+)\s+(\d{1,2})', caseSensitive: false);

/// Tekst in de notitie, bijv. "Pijntje: scheen 5".
String painNote(PainSpot spot, int severity) => 'Pijntje: ${spot.label} ${severity.clamp(1, 10)}';

/// Haalt de pijntjes uit een notitie (een run kan er meerdere hebben).
List<(PainSpot, int)> parsePain(String? note) {
  if (note == null || !note.contains('Pijntje')) return const [];
  return [
    for (final m in _re.allMatches(note))
      if (PainSpot.values.where((s) => s.label == m.group(1)!.toLowerCase()).firstOrNull case final s?)
        (s, int.parse(m.group(2)!).clamp(1, 10)),
  ];
}

List<PainEntry> painEntries(List<Activity> runs) => [
      for (final a in runs)
        for (final (s, v) in parsePain(a.note)) PainEntry(a, s, v),
    ];

class PainPattern {
  const PainPattern({required this.spot, required this.count, required this.maxSeverity, required this.reasons, required this.seeProfessional});
  final PainSpot spot;

  /// Hoe vaak in de afgelopen 14 dagen.
  final int count;
  final int maxSeverity;

  /// Waar het mee samenhangt, bijv. "na lange runs".
  final List<String> reasons;

  /// 3× of meer, of erg (≥ 6): laat er iemand naar kijken.
  final bool seeProfessional;
}

/// Pijntjes die terugkomen (≥ 2× in 14 dagen op dezelfde plek, of één keer erg), met mogelijke oorzaken.
List<PainPattern> painPatterns(List<Activity> runs, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final recent = runs.where((a) => n.difference(a.startedAt).inDays <= 60 && !a.startedAt.isAfter(n)).toList();
  final entries = painEntries(recent).where((e) => n.difference(e.run.startedAt).inDays <= 14).toList();
  if (entries.isEmpty) return const [];

  final dists = [for (final a in recent) a.distanceMeters]..sort();
  final medianDist = dists.isEmpty ? 0.0 : dists[dists.length ~/ 2];
  final paces = [for (final a in recent) if (a.paceSecondsPerKm > 0) a.paceSecondsPerKm]..sort();
  final medianPace = paces.isEmpty ? 0.0 : paces[paces.length ~/ 2];

  double kmBefore(DateTime t, int fromDays, int toDays) => recent
      .where((a) => a.startedAt.isBefore(t.subtract(Duration(days: fromDays))) && !a.startedAt.isBefore(t.subtract(Duration(days: toDays))))
      .fold<double>(0, (s, a) => s + a.distanceMeters / 1000);

  final out = <PainPattern>[];
  for (final spot in PainSpot.values) {
    final es = entries.where((e) => e.spot == spot).toList();
    if (es.isEmpty) continue;
    final maxSev = es.map((e) => e.severity).reduce((a, b) => a > b ? a : b);
    if (es.length < 2 && maxSev < 6) continue;
    final reasons = <String>[];
    final long = es.where((e) => medianDist > 0 && e.run.distanceMeters >= medianDist * 1.3).length;
    if (long * 2 >= es.length && long > 0) reasons.add('na langere runs');
    final fast = es.where((e) => medianPace > 0 && e.run.paceSecondsPerKm > 0 && e.run.paceSecondsPerKm <= medianPace * 0.95).length;
    if (fast * 2 >= es.length && fast > 0) reasons.add('na snellere runs');
    final ramp = es.where((e) {
      final week = kmBefore(e.run.startedAt, -1, 7);
      final base = kmBefore(e.run.startedAt, 7, 28) / 3;
      return base > 5 && week > base * 1.3;
    }).length;
    if (ramp * 2 >= es.length && ramp > 0) reasons.add('na een week met veel meer kilometers dan normaal');
    final shoes = <String, int>{};
    for (final e in es) {
      final s = e.run.shoeId;
      if (s != null) shoes[s] = (shoes[s] ?? 0) + 1;
    }
    for (final MapEntry(key: shoe, value: c) in shoes.entries) {
      final share = recent.where((a) => a.shoeId == shoe).length / recent.length;
      if (c == es.length && es.length >= 2 && share < 0.7) reasons.add('steeds met dezelfde schoenen');
    }
    out.add(PainPattern(spot: spot, count: es.length, maxSeverity: maxSev, reasons: reasons, seeProfessional: es.length >= 3 || maxSev >= 6));
  }
  out.sort((a, b) => b.count.compareTo(a.count));
  return out;
}

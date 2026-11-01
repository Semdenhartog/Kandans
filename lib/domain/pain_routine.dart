import 'pain_log.dart';
import 'strength.dart';

/// Krachtroutine op maat: oefeningen die passen bij je pijntjes (kuit, knie, heup …).
/// Gebruikt de bestaande Kadans-oefeningen; geen behandeling, wel de bekende basis.
const _forSpot = <PainSpot, List<String>>{
  PainSpot.calf: ['Langzaam kuitheffen op één been', 'Kuitheffen met gebogen knie', 'Kuit tegen de muur', 'Enkel naar de muur'],
  PainSpot.achilles: ['Langzaam kuitheffen op één been', 'Kuitheffen met gebogen knie', 'Enkel naar de muur'],
  PainSpot.shin: ['Op je hakken lopen', 'Kuitheffen', 'Enkelrondjes', 'Korte voet'],
  PainSpot.knee: ['Squat met pauze', 'Schelpje', 'Been zijwaarts heffen', 'Bilbrug'],
  PainSpot.hip: ['Schelpje', 'Been zijwaarts heffen', 'Eenbenige bilbrug', 'Zijplank'],
  PainSpot.hamstring: ['Bilbrug', 'Eenbenige bilbrug', 'Achterkant bovenbeen staand'],
  PainSpot.back: ['Dead bug', 'Vogel-hond', 'Kat en koe', 'Zijplank'],
  PainSpot.foot: ['Korte voet', 'Voetzool rollen', 'Enkelrondjes', 'Kuitheffen'],
};

Exercise? _find(String name) {
  for (final r in Routine.all) {
    for (final e in r.exercises) {
      if (e.name == name) return e;
    }
  }
  return null;
}

/// Routine voor deze plekken (belangrijkste eerst), hooguit [max] oefeningen.
Routine? routineForPains(List<PainSpot> spots, {int max = 7}) {
  if (spots.isEmpty) return null;
  final names = <String>[];
  // Om de beurt per plek, zodat elk pijntje aan bod komt.
  for (var round = 0; round < 4 && names.length < max; round++) {
    for (final s in spots) {
      final list = _forSpot[s] ?? const [];
      if (round < list.length && !names.contains(list[round]) && names.length < max) names.add(list[round]);
    }
  }
  final exercises = [for (final n in names) if (_find(n) case final e?) e];
  if (exercises.isEmpty) return null;
  return Routine(
    id: 'pain-${spots.map((s) => s.name).join('-')}',
    title: 'Voor jouw pijntjes',
    subtitle: spots.map((s) => s.label).join(', '),
    icon: 'healing',
    exercises: exercises,
    rest: 20,
    note: 'Licht ongemak mag, scherpe pijn niet: dan stoppen. Blijft het, ga dan naar een fysiotherapeut.',
  );
}

/// Plekken die de laatste 14 dagen pijn deden, de ergste eerst.
List<PainSpot> recentPainSpots(List<PainEntry> entries, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final worst = <PainSpot, int>{};
  for (final e in entries) {
    if (n.difference(e.run.startedAt).inDays > 14) continue;
    worst[e.spot] = (worst[e.spot] ?? 0) + e.severity;
  }
  final list = worst.keys.toList()..sort((a, b) => worst[b]!.compareTo(worst[a]!));
  return list;
}

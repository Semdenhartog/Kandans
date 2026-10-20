import 'intervals.dart';
import 'training_plan.dart';

/// Schema's voor wie begint of terugkomt (zoals Runna's "New to Running" en "Return to Running"):
/// op tijd in plaats van tempo, met lopen en wandelen, en rustig opbouwend.
enum BeginnerProgram {
  start('Van nul naar 5 km', 'Begin met korte stukjes lopen en wandelen. Na een paar weken loop je 30 minuten achter elkaar.', 6, 16, 9),
  comeback('Terugkomen na een pauze', 'Na een blessure, ziekte of lange stop: rustig weer opbouwen naar 40 minuten lopen.', 4, 12, 6);

  const BeginnerProgram(this.title, this.description, this.minWeeks, this.maxWeeks, this.defaultWeeks);
  final String title;
  final String description;
  final int minWeeks;
  final int maxWeeks;
  final int defaultWeeks;
}

/// Eén stap in de opbouw: [reps] keer [run] seconden lopen met [walk] seconden wandelen; reps 1 en walk 0 = aan één stuk.
typedef _Level = ({int reps, int run, int walk});

const _start = <_Level>[
  (reps: 8, run: 60, walk: 90),
  (reps: 6, run: 90, walk: 120),
  (reps: 5, run: 120, walk: 90),
  (reps: 4, run: 180, walk: 90),
  (reps: 3, run: 300, walk: 120),
  (reps: 3, run: 420, walk: 120),
  (reps: 2, run: 600, walk: 120),
  (reps: 1, run: 1200, walk: 0),
  (reps: 1, run: 1500, walk: 0),
];

const _comeback = <_Level>[
  (reps: 5, run: 240, walk: 60),
  (reps: 4, run: 360, walk: 60),
  (reps: 3, run: 540, walk: 60),
  (reps: 1, run: 1500, walk: 0),
  (reps: 1, run: 1800, walk: 0),
  (reps: 1, run: 2100, walk: 0),
];

String _min(int s) => s % 60 == 0 ? '${s ~/ 60} min' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')} min';

PlanSession _session(DateTime date, int week, _Level l, {String? title, String? extra}) {
  final continuous = l.reps == 1 && l.walk == 0;
  final plan = continuous
      ? IntervalPlan('${_min(l.run)} lopen', [
          const IntervalStep(StepKind.warmup, seconds: 300),
          IntervalStep(StepKind.work, seconds: l.run),
          const IntervalStep(StepKind.cooldown, seconds: 300),
        ], walkRun: true)
      : IntervalPlan.walkRun(reps: l.reps, runSeconds: l.run, walkSeconds: l.walk, name: '${l.reps} × ${_min(l.run)} lopen');
  final what = continuous
      ? '5 minuten stevig wandelen, dan ${_min(l.run)} rustig hardlopen aan één stuk, en 5 minuten uitwandelen.'
      : '5 minuten stevig wandelen, dan ${l.reps} keer ${_min(l.run)} hardlopen met telkens ${_min(l.walk)} wandelen, en 5 minuten uitwandelen.';
  return PlanSession(
    date: date,
    kind: SessionKind.easy,
    week: week,
    title: title ?? (continuous ? '${_min(l.run)} aan één stuk' : '${l.reps} × ${_min(l.run)} lopen'),
    description: '$what Loop zo rustig dat je kunt praten; te zwaar? Wandel langer, dat is prima.${extra == null ? '' : ' $extra'}',
    intervals: plan,
  );
}

/// Bouwt een beginnersschema van [weeks] weken met 3 loopdagen (of zoveel als [runDays]), vanaf [start].
/// Bij meer weken dan stappen wordt elke stap langer herhaald, zodat de opbouw rustiger gaat.
List<PlanSession> buildBeginnerPlan(BeginnerProgram p, {required DateTime start, required List<int> runDays, int? weeks}) {
  final levels = p == BeginnerProgram.start ? _start : _comeback;
  final n = (weeks ?? p.defaultWeeks).clamp(p.minWeeks, p.maxWeeks);
  final days = ([...runDays]..sort()).take(4).toList();
  if (days.isEmpty) return const [];
  final day0 = DateTime(start.year, start.month, start.day);
  final out = <PlanSession>[];
  for (var w = 0; w < n; w++) {
    final level = levels[(w * levels.length / n).floor().clamp(0, levels.length - 1)];
    for (final d in days) {
      final date = DateTime(day0.year, day0.month, day0.day + w * 7 + ((d - day0.weekday) % 7));
      out.add(_session(date, w + 1, level));
    }
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  // De laatste training is de mijlpaal.
  if (out.isNotEmpty) {
    final last = out.removeLast();
    final finale = p == BeginnerProgram.start
        ? _session(last.date, last.week, (reps: 1, run: 1800, walk: 0),
            title: 'Jouw eerste 30 minuten (of 5 km)!', extra: 'Dit is je mijlpaal. Neem de tijd, geniet ervan.')
        : _session(last.date, last.week, (reps: 1, run: 2400, walk: 0),
            title: '40 minuten: je bent terug!', extra: 'Daarna kun je een schema naar een afstand kiezen.');
    out.add(finale);
  }
  return out;
}

import 'run_recorder.dart' show spokenDuration;

enum StepKind {
  warmup('Inlopen'),
  work('Snel'),
  rest('Rustig'),
  cooldown('Uitlopen');

  const StepKind(this.label);
  final String label;
}

/// Eén stap: op tijd (seconden) of op afstand (meters).
class IntervalStep {
  const IntervalStep(this.kind, {this.seconds, this.meters}) : assert((seconds == null) != (meters == null));
  final StepKind kind;
  final int? seconds;
  final int? meters;

  bool get byDistance => meters != null;

  String get amount => byDistance ? (meters! >= 1000 && meters! % 100 == 0 ? '${(meters! / 1000).toString().replaceAll('.', ',').replaceAll(RegExp(r',0$'), '')} km' : '$meters m') : _time(seconds!);

  String get spokenAmount => byDistance
      ? (meters! >= 1000 && meters! % 1000 == 0 ? '${meters! ~/ 1000} kilometer' : '$meters meter')
      : (seconds! < 60 ? '$seconds seconden' : (seconds! % 60 == 0 ? '${seconds! ~/ 60} ${seconds! == 60 ? 'minuut' : 'minuten'}' : spokenDuration(seconds!.toDouble())));

  Map<String, dynamic> toJson() => {'k': kind.name, if (seconds != null) 's': seconds, if (meters != null) 'm': meters};

  static IntervalStep? fromJson(Object? j) {
    if (j is! Map) return null;
    final k = StepKind.values.where((x) => x.name == j['k']).firstOrNull;
    final s = (j['s'] as num?)?.toInt(), m = (j['m'] as num?)?.toInt();
    if (k == null || (s == null) == (m == null)) return null;
    return IntervalStep(k, seconds: s, meters: m);
  }
}

String _time(int s) => s < 60 ? '$s s' : (s % 60 == 0 ? '${s ~/ 60} min' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}');

class IntervalPlan {
  const IntervalPlan(this.name, this.steps);
  final String name;
  final List<IntervalStep> steps;

  int get reps => steps.where((s) => s.kind == StepKind.work).length;

  /// Bouwt een schema: inlopen, [reps] keer snel + rustig, uitlopen.
  factory IntervalPlan.build({
    String? name,
    int warmupMin = 10,
    required int reps,
    int? workSeconds,
    int? workMeters,
    required int restSeconds,
    int cooldownMin = 5,
  }) {
    final work = IntervalStep(StepKind.work, seconds: workMeters == null ? workSeconds ?? 60 : null, meters: workMeters);
    return IntervalPlan(name ?? '$reps × ${work.amount}', [
      if (warmupMin > 0) IntervalStep(StepKind.warmup, seconds: warmupMin * 60),
      for (var i = 0; i < reps; i++) ...[
        work,
        if (i < reps - 1 && restSeconds > 0) IntervalStep(StepKind.rest, seconds: restSeconds),
      ],
      if (cooldownMin > 0) IntervalStep(StepKind.cooldown, seconds: cooldownMin * 60),
    ]);
  }

  static final presets = <IntervalPlan>[
    IntervalPlan.build(reps: 6, workMeters: 400, restSeconds: 90),
    IntervalPlan.build(reps: 5, workSeconds: 180, restSeconds: 120),
    IntervalPlan.build(reps: 10, workSeconds: 60, restSeconds: 60),
    IntervalPlan.build(reps: 4, workMeters: 1000, restSeconds: 120),
    IntervalPlan('Piramide 1-2-3-2-1 min', [
      const IntervalStep(StepKind.warmup, seconds: 600),
      for (final (i, m) in [1, 2, 3, 2, 1].indexed) ...[
        IntervalStep(StepKind.work, seconds: m * 60),
        if (i < 4) IntervalStep(StepKind.rest, seconds: m * 60 ~/ 2 + 30),
      ],
      const IntervalStep(StepKind.cooldown, seconds: 300),
    ]),
  ];

  Map<String, dynamic> toJson() => {'name': name, 'steps': [for (final s in steps) s.toJson()]};

  static IntervalPlan? fromJson(Object? j) {
    if (j is! Map || j['steps'] is! List) return null;
    final steps = [for (final s in j['steps'] as List) IntervalStep.fromJson(s)].whereType<IntervalStep>().toList();
    if (steps.isEmpty) return null;
    return IntervalPlan((j['name'] as String?) ?? 'Intervallen', steps);
  }
}

/// Wat de stem moet zeggen.
class IntervalCue {
  const IntervalCue(this.text, {this.stepChanged = false, this.finished = false});
  final String text;
  final bool stepChanged;
  final bool finished;
}

/// Houdt bij in welke stap je zit, op basis van bewegende tijd en afstand (pauzes tellen niet).
class IntervalTracker {
  IntervalTracker(this.plan);
  final IntervalPlan plan;

  int index = -1;
  double _stepStartTime = 0;
  double _stepStartDistance = 0;
  bool _warned = false;
  bool _halfway = false;
  bool get finished => index >= plan.steps.length;
  IntervalStep? get current => index >= 0 && index < plan.steps.length ? plan.steps[index] : null;
  IntervalStep? get next => index + 1 < plan.steps.length ? plan.steps[index + 1] : null;

  /// Hoeveelste snelle stuk (1-based), of 0.
  int get workNumber {
    var n = 0;
    for (var i = 0; i <= index && i < plan.steps.length; i++) {
      if (plan.steps[i].kind == StepKind.work) n++;
    }
    return current?.kind == StepKind.work ? n : 0;
  }

  double _elapsed(double t) => t - _stepStartTime;
  double _covered(double d) => d - _stepStartDistance;

  /// Resterend in de huidige stap: seconden of meters.
  double remaining(double movingSeconds, double distance) {
    final s = current;
    if (s == null) return 0;
    return s.byDistance ? (s.meters! - _covered(distance)).clamp(0, double.infinity) : (s.seconds! - _elapsed(movingSeconds)).clamp(0, double.infinity);
  }

  /// 0..1 voortgang in de huidige stap.
  double progress(double movingSeconds, double distance) {
    final s = current;
    if (s == null) return finished ? 1 : 0;
    final total = (s.byDistance ? s.meters! : s.seconds!).toDouble();
    return total <= 0 ? 1 : (1 - remaining(movingSeconds, distance) / total).clamp(0, 1);
  }

  IntervalCue start(double movingSeconds, double distance) => _enter(0, movingSeconds, distance)!;

  IntervalCue? _enter(int i, double t, double d) {
    index = i;
    _stepStartTime = t;
    _stepStartDistance = d;
    _warned = false;
    _halfway = false;
    final s = current;
    if (s == null) return const IntervalCue('Intervallen klaar. Goed gedaan! Loop rustig uit of stop je run.', stepChanged: true, finished: true);
    final reps = plan.reps;
    final text = switch (s.kind) {
      StepKind.warmup => 'Inlopen, ${s.spokenAmount} rustig.',
      StepKind.work => 'Snel! Interval $workNumber van $reps, ${s.spokenAmount}.',
      StepKind.rest => 'Rustig. ${s.spokenAmount} herstellen.',
      StepKind.cooldown => 'Uitlopen, ${s.spokenAmount} rustig.',
    };
    return IntervalCue(text, stepChanged: true);
  }

  /// Aanroepen bij elke update. Geeft een tekst als er iets te zeggen is.
  IntervalCue? update(double movingSeconds, double distance) {
    final s = current;
    if (s == null) return null;
    final left = remaining(movingSeconds, distance);
    if (left <= 0) return _enter(index + 1, movingSeconds, distance);
    // Aftellen op tijd: 10 seconden van tevoren; op afstand: 100 m.
    final warnAt = s.byDistance ? 100 : 10;
    final total = s.byDistance ? s.meters! : s.seconds!;
    if (!_warned && total > warnAt * 2 && left <= warnAt) {
      _warned = true;
      final n = next;
      final then = n == null ? 'daarna klaar' : 'daarna ${n.kind.label.toLowerCase()}';
      return IntervalCue(s.byDistance ? 'Nog 100 meter, $then.' : 'Nog 10 seconden, $then.');
    }
    if (!_halfway && s.kind == StepKind.work && total >= (s.byDistance ? 800 : 180) && left <= total / 2) {
      _halfway = true;
      return const IntervalCue('Halverwege. Hou vol!');
    }
    return null;
  }

  /// Sla de huidige stap over.
  IntervalCue? skip(double movingSeconds, double distance) => finished ? null : _enter(index + 1, movingSeconds, distance);
}

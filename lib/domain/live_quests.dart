/// Live opdrachten tijdens een gewone run: af en toe een korte uitdaging
/// ("sprint 20 seconden onder 4:45/km"), met uitslag via de stem.
///
/// De doelen hangen af van jouw eigen gemiddelde tempo in deze run, zodat ze
/// voor een beginner en een snelle loper even pittig zijn.
library;

enum QuestKind { sprint, fastMinute, steadyKm, strongFinish }

class Quest {
  const Quest({
    required this.kind,
    required this.targetPace,
    this.seconds,
    this.meters,
  });

  final QuestKind kind;

  /// Doeltempo in s/km (sneller of gelijk = gehaald).
  final double targetPace;

  /// Tijdsopdracht (s) of afstandsopdracht (m): precies één van beide.
  final double? seconds;
  final double? meters;

  String get title => switch (kind) {
        QuestKind.sprint => 'Sprint ${seconds!.round()} s',
        QuestKind.fastMinute => 'Snelle minuut',
        QuestKind.steadyKm => 'Kilometer op tempo',
        QuestKind.strongFinish => 'Sterke finish',
      };
}

/// Afloop van een opdracht.
class QuestResult {
  const QuestResult(this.quest, this.pace, this.success);
  final Quest quest;
  final double pace;
  final bool success;
}

/// Wat de opdrachtenleider op een moment te melden heeft.
class QuestCue {
  const QuestCue(this.text, {this.started, this.result, this.countdown = false});
  final String text;
  final Quest? started;
  final QuestResult? result;

  /// Een korte tussenmelding ("nog 10 seconden").
  final bool countdown;
}

String questPace(double secPerKm) {
  final s = secPerKm.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String _spoken(double secPerKm) {
  final s = secPerKm.round();
  final m = s ~/ 60, r = s % 60;
  return r == 0 ? '$m minuten per kilometer' : '$m ${r.toString().padLeft(2, '0')} per kilometer';
}

/// Volgt de opdrachten. Roep [update] aan bij elke GPS-meting.
/// Hoe pittig de opdrachten zijn.
enum QuestLevel {
  easy('Rustig', 0.6),
  normal('Normaal', 1),
  hard('Pittig', 1.4);

  const QuestLevel(this.label, this.factor);
  final String label;

  /// Vermenigvuldigt hoeveel sneller dan je gemiddelde je moet lopen.
  final double factor;
}

class QuestMaster {
  QuestMaster({
    this.warmupSeconds = 8 * 60,
    this.warmupMeters = 1200,
    this.gapSeconds = 5 * 60,
    this.targetMeters,
    this.level = QuestLevel.normal,
  });

  /// Rustig, normaal of pittig.
  final QuestLevel level;

  /// Eerst rustig inlopen.
  final double warmupSeconds;
  final double warmupMeters;

  /// Rust tussen twee opdrachten.
  final double gapSeconds;

  /// Geplande afstand (voor de sterke finish), of null.
  final double? targetMeters;

  static const _cycle = [QuestKind.sprint, QuestKind.fastMinute, QuestKind.steadyKm, QuestKind.sprint];

  Quest? _active;
  double _startT = 0, _startD = 0;
  double _lastEnd = -1e9;
  int _next = 0;
  bool _finishDone = false;
  bool _tenSaid = false;
  final List<QuestResult> results = [];

  Quest? get active => _active;
  int get done => results.where((r) => r.success).length;
  int get total => results.length;

  /// Wat er nog over is van de actieve opdracht (s of m).
  double remaining(double t, double d) {
    final q = _active;
    if (q == null) return 0;
    return q.seconds != null ? (q.seconds! - (t - _startT)).clamp(0, q.seconds!) : (q.meters! - (d - _startD)).clamp(0, q.meters!);
  }

  /// Voortgang 0..1 van de actieve opdracht.
  double progress(double t, double d) {
    final q = _active;
    if (q == null) return 0;
    final whole = q.seconds ?? q.meters!;
    return (1 - remaining(t, d) / whole).clamp(0, 1).toDouble();
  }

  Quest _make(QuestKind kind, double base) {
    final f = level.factor;
    // Sneller dan je gemiddelde, met een ondergrens zodat het haalbaar blijft.
    double pace(double faster, double floor) => (base - faster * f).clamp(floor, 900).toDouble();
    return switch (kind) {
      QuestKind.sprint => Quest(kind: kind, targetPace: pace(50, 150), seconds: level == QuestLevel.hard ? 30 : 20),
      QuestKind.fastMinute => Quest(kind: kind, targetPace: pace(25, 160), seconds: 60),
      QuestKind.steadyKm => Quest(kind: kind, targetPace: pace(10, 170), meters: 1000),
      QuestKind.strongFinish => Quest(kind: kind, targetPace: pace(15, 160), meters: 500),
    };
  }

  String _intro(Quest q) => switch (q.kind) {
        QuestKind.sprint => 'Opdracht: sprint ${q.seconds!.round()} seconden, sneller dan ${_spoken(q.targetPace)}. Start nu!',
        QuestKind.fastMinute => 'Opdracht: een snelle minuut, onder ${_spoken(q.targetPace)}. Go!',
        QuestKind.steadyKm => 'Opdracht: loop de komende kilometer onder ${_spoken(q.targetPace)}. Rustig opbouwen.',
        QuestKind.strongFinish => 'Laatste opdracht: sterke finish. De laatste 500 meter onder ${_spoken(q.targetPace)}.',
      };

  /// [t] = bewegende tijd (s), [d] = afstand (m), [avgPace] = gemiddeld tempo tot nu toe (s/km, 0 = onbekend).
  QuestCue? update(double t, double d, double avgPace) {
    final q = _active;
    if (q != null) {
      final left = remaining(t, d);
      if (q.seconds != null && q.seconds! >= 30 && !_tenSaid && left <= 10 && left > 0) {
        _tenSaid = true;
        return const QuestCue('Nog 10 seconden!', countdown: true);
      }
      if (left > 0) return null;
      final dt = t - _startT, dd = d - _startD;
      final pace = dd > 5 ? dt / (dd / 1000) : 0.0;
      final ok = pace > 0 && pace <= q.targetPace + 0.5;
      final r = QuestResult(q, pace, ok);
      results.add(r);
      _active = null;
      _lastEnd = t;
      final shown = pace > 0 ? questPace(pace) : 'onbekend';
      final text = ok
          ? 'Gehaald! Je liep $shown per kilometer. Rustig uitlopen.'
          : pace > 0
              ? 'Net niet: $shown per kilometer. Volgende keer beter. Rustig aan nu.'
              : 'Opdracht voorbij, maar het tempo kon ik niet goed meten.';
      return QuestCue(text, result: r);
    }

    if (avgPace <= 0 || avgPace > 900) return null;

    // Sterke finish als je een doelafstand hebt en er nog 500 m over is.
    final tm = targetMeters;
    if (tm != null && !_finishDone && tm >= 3000 && d >= tm - 500 && d < tm - 300) {
      _finishDone = true;
      return _begin(_make(QuestKind.strongFinish, avgPace), t, d);
    }

    if (t < warmupSeconds || d < warmupMeters) return null;
    if (t - _lastEnd < gapSeconds) return null;
    // Geen nieuwe opdracht vlak voor het einde van een geplande afstand.
    if (tm != null && d > tm - 1300) return null;
    final kind = _cycle[_next % _cycle.length];
    _next++;
    return _begin(_make(kind, avgPace), t, d);
  }

  QuestCue _begin(Quest q, double t, double d) {
    _active = q;
    _startT = t;
    _startD = d;
    _tenSaid = false;
    return QuestCue(_intro(q), started: q);
  }

  /// Opdracht overslaan (telt niet mee); de rust tot de volgende begint opnieuw.
  void skip(double t) {
    if (_active == null) return;
    _active = null;
    _lastEnd = t;
  }

  /// Korte samenvatting voor het einde van de run, of null als er geen opdrachten waren.
  String? summary() {
    if (results.isEmpty) return null;
    return '$done van de $total opdrachten gehaald.';
  }
}

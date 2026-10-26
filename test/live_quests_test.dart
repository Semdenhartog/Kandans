import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/live_quests.dart';

/// Loopt [seconds] seconden in stappen van 1 s met [pace] s/km en geeft alle meldingen terug.
List<QuestCue> run(QuestMaster m, double seconds, double Function(double t) pace, {double avg = 360}) {
  final cues = <QuestCue>[];
  var d = 0.0;
  for (var t = 1.0; t <= seconds; t++) {
    d += 1000 / pace(t);
    final c = m.update(t, d, avg);
    if (c != null) cues.add(c);
  }
  return cues;
}

void main() {
  test('geen opdracht tijdens het inlopen', () {
    final m = QuestMaster();
    expect(run(m, 7 * 60, (_) => 360), isEmpty);
  });

  test('sprint komt na het inlopen en wordt gehaald als je sneller loopt', () {
    final m = QuestMaster();
    var sprintFrom = -1.0;
    final cues = <QuestCue>[];
    var d = 0.0;
    for (var t = 1.0; t <= 9 * 60; t++) {
      final fast = sprintFrom >= 0 && t - sprintFrom <= 20;
      d += 1000 / (fast ? 280 : 360);
      final c = m.update(t, d, 360);
      if (c != null) {
        cues.add(c);
        if (c.started != null) sprintFrom = t;
      }
    }
    expect(cues.first.started?.kind, QuestKind.sprint);
    expect(cues.first.started!.targetPace, 310); // 6:00 − 50 s
    final result = cues.firstWhere((c) => c.result != null).result!;
    expect(result.success, isTrue);
    expect(m.done, 1);
    expect(m.summary(), '1 van de 1 opdrachten gehaald.');
  });

  test('te langzaam = net niet', () {
    final m = QuestMaster(warmupSeconds: 0, warmupMeters: 0);
    final cues = run(m, 40, (_) => 360);
    final r = cues.firstWhere((c) => c.result != null).result!;
    expect(r.success, isFalse);
    expect(cues.last.text, startsWith('Net niet'));
  });

  test('rust tussen twee opdrachten', () {
    final m = QuestMaster(warmupSeconds: 0, warmupMeters: 0, gapSeconds: 300);
    final cues = run(m, 200, (_) => 300);
    expect(cues.where((c) => c.started != null).length, 1);
  });

  test('sterke finish bij een geplande afstand', () {
    final m = QuestMaster(warmupSeconds: 1e9, targetMeters: 5000);
    final cues = run(m, 30 * 60, (_) => 330);
    expect(cues.any((c) => c.started?.kind == QuestKind.strongFinish), isTrue);
  });

  test('tempo-tekst', () {
    expect(questPace(305), '5:05');
  });

  test('overslaan telt niet mee', () {
    final m = QuestMaster(warmupSeconds: 0, warmupMeters: 0);
    m.update(1, 3, 360);
    expect(m.active, isNotNull);
    m.skip(5);
    expect(m.active, isNull);
    expect(m.total, 0);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/start_time_scoring.dart';
import 'package:runwise/domain/usual_time.dart';

void main() {
  final now = DateTime(2026, 10, 23, 12);
  DateTime day(int daysAgo, int h, int m) => DateTime(2026, 10, 23 - daysAgo, h, m);

  group('je gewone looptijd', () {
    test('meestal rond half zeven', () {
      final runs = [day(1, 18, 20), day(3, 18, 35), day(5, 18, 30), day(8, 18, 45), day(10, 7, 30), day(12, 18, 25)];
      final u = usualStartTime(runs, now: now)!;
      expect(u.label, '18:30');
      expect(u.runs, 5);
      expect(u.share, closeTo(5 / 6, 0.01));
    });

    test('wisselende tijden (diensten): geen gewone tijd', () {
      final runs = [day(1, 7, 0), day(2, 13, 0), day(4, 19, 0), day(6, 10, 0), day(8, 16, 0), day(9, 21, 0)];
      expect(usualStartTime(runs, now: now), isNull);
    });

    test('te weinig runs, of te lang geleden', () {
      expect(usualStartTime([day(1, 18, 0), day(2, 18, 0), day(3, 18, 0)], now: now), isNull);
      expect(usualStartTime([for (var i = 0; i < 6; i++) day(70 + i, 18, 0)], now: now), isNull);
    });
  });

  group('ochtendmelding alleen als het uitmaakt', () {
    final hour = HourWeather(time: DateTime(2026, 10, 23, 18), temperature: 12, windSpeed: 10, isDay: true);
    StartTimeScore sc(int h, int score) =>
        StartTimeScore(start: DateTime(2026, 10, 23, h), score: score, weather: hour, reasons: const []);
    const usual = UsualTime(hour: 18, minute: 0, runs: 5, share: 0.8);

    test('zonder gewone tijd altijd sturen', () {
      expect(reminderDecision(best: sc(15, 90)).send, isTrue);
    });

    test('gewone tijd is prima: stil', () {
      expect(reminderDecision(best: sc(15, 84), usual: usual, atUsual: sc(18, 80)).send, isFalse);
      // Het beste moment ís je gewone tijd.
      expect(reminderDecision(best: sc(18, 90), usual: usual, atUsual: sc(18, 90)).send, isFalse);
    });

    test('ander moment duidelijk beter: sturen met uitleg', () {
      final d = reminderDecision(best: sc(15, 88), usual: usual, atUsual: sc(18, 70));
      expect(d.send, isTrue);
      expect(d.note, '18 punten beter dan je gewone tijd (18:00).');
    });

    test('gewone tijd slecht: waarschuwen', () {
      final d = reminderDecision(best: sc(18, 50), usual: usual, atUsual: sc(18, 50));
      expect(d.send, isTrue);
      expect(d.note, contains('lastig'));
    });

    test('je kunt die dag niet op je gewone tijd (dienst): sturen', () {
      expect(reminderDecision(best: sc(15, 84), usual: usual, atUsual: sc(18, 80), usualAllowed: false).send, isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/run_helpers.dart';

void main() {
  test('zonsondergang Barneveld eind oktober rond 16:25 UTC', () {
    final s = sunTimes(DateTime(2026, 10, 21), 52.14, 5.58);
    final set = s.sunset!.toUtc();
    // Echte waarde: ~16:25 UTC (18:25 zomertijd).
    expect(set.hour * 60 + set.minute, inInclusiveRange(16 * 60 + 15, 16 * 60 + 35));
    final rise = s.sunrise!.toUtc();
    expect(rise.hour * 60 + rise.minute, inInclusiveRange(6 * 60 + 5, 6 * 60 + 30));
  });

  test('donker-waarschuwing alleen als je na zonsondergang terug bent', () {
    final set = sunTimes(DateTime(2026, 10, 21), 52.14, 5.58).sunset!;
    expect(darkWarning(set.subtract(const Duration(minutes: 30)), const Duration(minutes: 60), 52.14, 5.58), isNotNull);
    expect(darkWarning(set.subtract(const Duration(hours: 3)), const Duration(minutes: 45), 52.14, 5.58), isNull);
  });

  test('terug naar start: achter je als je er recht vanaf loopt', () {
    final track = [for (var i = 0; i < 10; i++) LatLng(52.0 + i * 0.0005, 5.6)];
    final b = backToStart(track)!;
    expect(b.meters, greaterThan(400));
    expect(directionWords(b.relative!), 'achter je');
  });

  test('weekdoel-voorstellen rond je gemiddelde', () {
    expect(weekGoalSuggestions(28), [25.0, 30.0, 35.0]);
    expect(weekGoalSuggestions(0), [10.0, 15.0, 20.0]);
  });
}

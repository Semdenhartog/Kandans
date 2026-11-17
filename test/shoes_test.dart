import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/shoes.dart';

Activity _run(DateTime at, double m, {String? shoe}) =>
    Activity(startedAt: at, distanceMeters: m, movingTimeSeconds: (m / 3).round(), shoeId: shoe);

void main() {
  final t0 = DateTime(2026, 1, 1);

  test('kilometers: startstand + runs op de schoen', () {
    final s = Shoe(id: 'a', name: 'A', startKm: 100, createdAt: t0);
    final runs = [_run(DateTime(2026, 2, 1), 10000, shoe: 'a'), _run(DateTime(2026, 2, 2), 5000, shoe: 'b')];
    expect(shoeKm(s, runs), closeTo(110, 0.001));
  });

  test('runs zonder schoen tellen alleen voor de standaardschoen, vanaf toevoegen', () {
    final d = Shoe(id: 'a', name: 'A', isDefault: true, createdAt: DateTime(2026, 3, 1));
    final runs = [_run(DateTime(2026, 2, 1), 8000), _run(DateTime(2026, 3, 5), 6000)];
    expect(shoeKm(d, runs), closeTo(6, 0.001));
    final other = Shoe(id: 'b', name: 'B', createdAt: t0);
    expect(shoeKm(other, runs), 0);
  });

  test('afgeschreven standaardschoen krijgt geen losse runs meer', () {
    final d = Shoe(id: 'a', name: 'A', isDefault: true, retired: true, createdAt: t0);
    expect(shoeKm(d, [_run(DateTime(2026, 2, 1), 5000)]), 0);
    expect(defaultShoe([d]), isNull);
  });

  test('versleten vanaf 90% van de grens', () {
    final s = Shoe(id: 'a', name: 'A', startKm: 630, limitKm: 700, createdAt: t0);
    expect(shoeWornOut(s, const []), isTrue);
    expect(shoeWornOut(Shoe(id: 'a', name: 'A', startKm: 629, limitKm: 700, createdAt: t0), const []), isFalse);
  });

  test('geen schoenen: geen standaardschoen', () {
    expect(defaultShoe(const []), isNull);
  });
}

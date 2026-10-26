import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/features/challenges/invite_card.dart';

void main() {
  test('uitnodigingslink bevat de code', () {
    final link = inviteLink('K7QX2M');
    expect(link, endsWith('/vriend.html?code=K7QX2M'));
    expect(link, startsWith('https://'));
  });

  test('vriendcode uit klembord', () {
    expect(friendCodeFrom('https://x.github.io/Runwise/vriend.html?code=k7qx2m'), 'K7QX2M');
    expect(friendCodeFrom('  K7QX2M '), 'K7QX2M');
    expect(friendCodeFrom('Hallo daar'), isNull);
    expect(friendCodeFrom('ABCDEF'), isNull); // geen cijfer: waarschijnlijk een gewoon woord
  });
}

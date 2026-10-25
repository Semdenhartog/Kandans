import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/features/challenges/invite_card.dart';

void main() {
  test('uitnodigingslink bevat de code', () {
    final link = inviteLink('K7QX2M');
    expect(link, endsWith('/vriend.html?code=K7QX2M'));
    expect(link, startsWith('https://'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/services/community_service.dart';

void main() {
  test('status uit de server lezen', () {
    final s = CommunityStatus.fromJson({
      'joined': true,
      'nickname': 'Sem',
      'friend_code': 'K7QX2M',
      'boards': [
        {'key': 'km-2026-11', 'title': 'Kilometers in november', 'unit': 'km', 'start': '2026-11-01', 'end': '2026-12-01', 'kind': 'km'},
      ],
    });
    expect(s.joined, isTrue);
    expect(s.friendCode, 'K7QX2M');
    expect(s.boards.single.unit, 'km');
  });

  test('niet meedoen: lege velden', () {
    final s = CommunityStatus.fromJson({'joined': false, 'nickname': null, 'friend_code': null, 'boards': []});
    expect(s.joined, isFalse);
    expect(s.nickname, isNull);
    expect(s.boards, isEmpty);
  });

  test('rij met hele getallen als waarde', () {
    final r = BoardRow.fromJson({'rank': 3, 'nickname': 'Lotte', 'value': 120, 'me': false, 'friend': true});
    expect(r.value, 120.0);
    expect(r.friend, isTrue);
    expect(r.me, isFalse);
  });
}

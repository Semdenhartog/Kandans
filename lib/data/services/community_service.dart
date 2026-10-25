import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';

/// Een ranglijst die nu loopt.
class BoardInfo {
  const BoardInfo({required this.key, required this.title, required this.unit});
  final String key;
  final String title;
  final String unit;

  factory BoardInfo.fromJson(Map<String, dynamic> j) =>
      BoardInfo(key: j['key'] as String, title: j['title'] as String, unit: j['unit'] as String);
}

/// Of je meedoet, met welke bijnaam en vriendcode.
class CommunityStatus {
  const CommunityStatus({required this.joined, this.nickname, this.friendCode, this.boards = const []});
  final bool joined;
  final String? nickname;
  final String? friendCode;
  final List<BoardInfo> boards;

  factory CommunityStatus.fromJson(Map<String, dynamic> j) => CommunityStatus(
        joined: j['joined'] == true,
        nickname: j['nickname'] as String?,
        friendCode: j['friend_code'] as String?,
        boards: [for (final b in (j['boards'] as List? ?? const []).cast<Map>()) BoardInfo.fromJson(b.cast<String, dynamic>())],
      );
}

class BoardRow {
  const BoardRow({required this.rank, required this.nickname, required this.value, this.me = false, this.friend = false});
  final int rank;
  final String nickname;
  final double value;
  final bool me;
  final bool friend;

  factory BoardRow.fromJson(Map<String, dynamic> j) => BoardRow(
        rank: (j['rank'] as num).toInt(),
        nickname: j['nickname'] as String,
        value: (j['value'] as num).toDouble(),
        me: j['me'] == true,
        friend: j['friend'] == true,
      );
}

class BoardResult {
  const BoardResult({required this.rows, this.mine, this.total = 0});
  final List<BoardRow> rows;
  final BoardRow? mine;
  final int total;
}

/// "Samen": ranglijsten via de server (edge function "community").
class CommunityService {
  CommunityService(this._db);
  final SupabaseClient _db;

  Future<Map<String, dynamic>> _call(String action, [Map<String, dynamic> extra = const {}]) async {
    try {
      final res = await _db.functions.invoke('community', body: {'action': action, ...extra});
      return (res.data as Map).cast<String, dynamic>();
    } on FunctionException catch (e) {
      final details = e.details is Map ? (e.details as Map).cast<String, dynamic>() : <String, dynamic>{};
      if (e.status == 404 && details['error'] == null) throw Exception('Samen lopen is nog niet beschikbaar.');
      throw Exception(details['error'] ?? 'Even geen verbinding met de ranglijst. Probeer het later opnieuw.');
    }
  }

  Future<CommunityStatus> status() async => CommunityStatus.fromJson(await _call('status'));

  Future<CommunityStatus> join(String nickname) async => CommunityStatus.fromJson(await _call('join', {'nickname': nickname}));

  Future<void> leave() => _call('leave');

  Future<void> refresh() => _call('refresh');

  Future<BoardResult> board(String key, {bool friends = false}) async {
    final m = await _call('board', {'board': key, 'scope': friends ? 'friends' : 'all'});
    return BoardResult(
      rows: [for (final r in (m['rows'] as List? ?? const []).cast<Map>()) BoardRow.fromJson(r.cast<String, dynamic>())],
      mine: m['mine'] is Map ? BoardRow.fromJson((m['mine'] as Map).cast<String, dynamic>()) : null,
      total: (m['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// Geeft de bijnaam van de nieuwe vriend terug.
  Future<String> follow(String code) async => (await _call('follow', {'code': code}))['nickname'] as String;

  Future<void> unfollow(String nickname) => _call('unfollow', {'nickname': nickname});

  Future<List<String>> friends() async => [for (final f in (await _call('friends'))['friends'] as List? ?? const []) f.toString()];
}

final communityServiceProvider = Provider<CommunityService>((ref) => CommunityService(ref.watch(supabaseProvider)));

final communityStatusProvider = FutureProvider<CommunityStatus>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(communityServiceProvider).status();
});

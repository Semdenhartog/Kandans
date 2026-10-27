import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';

/// Onderwerpen in de community (sleutel in de database → naam in de app).
const communityTopics = <String, String>{
  'algemeen': 'Algemeen',
  'beginners': 'Beginners',
  'routes': 'Routes en plekken',
  'wedstrijden': 'Wedstrijden',
  'blessures': 'Blessures en herstel',
  'spullen': 'Schoenen en spullen',
  'afspreken': 'Samen lopen',
};

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.topic,
    required this.body,
    required this.createdAt,
    required this.nickname,
    this.likes = 0,
    this.comments = 0,
    this.liked = false,
    this.mine = false,
    this.canDelete = false,
  });

  final int id;
  final String topic;
  final String body;
  final DateTime createdAt;
  final String nickname;
  final int likes;
  final int comments;
  final bool liked;
  final bool mine;
  final bool canDelete;

  factory CommunityPost.fromJson(Map<String, dynamic> j) => CommunityPost(
        id: (j['id'] as num).toInt(),
        topic: j['topic'] as String? ?? 'algemeen',
        body: j['body'] as String? ?? '',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        nickname: j['nickname'] as String? ?? 'loper',
        likes: (j['likes'] as num?)?.toInt() ?? 0,
        comments: (j['comments'] as num?)?.toInt() ?? 0,
        liked: j['liked'] == true,
        mine: j['mine'] == true,
        canDelete: j['can_delete'] == true,
      );

  CommunityPost copyWith({int? likes, bool? liked, int? comments}) => CommunityPost(
        id: id,
        topic: topic,
        body: body,
        createdAt: createdAt,
        nickname: nickname,
        likes: likes ?? this.likes,
        comments: comments ?? this.comments,
        liked: liked ?? this.liked,
        mine: mine,
        canDelete: canDelete,
      );
}

class CommunityComment {
  const CommunityComment({required this.id, required this.body, required this.createdAt, required this.nickname, this.mine = false, this.canDelete = false});
  final int id;
  final String body;
  final DateTime createdAt;
  final String nickname;
  final bool mine;
  final bool canDelete;

  factory CommunityComment.fromJson(Map<String, dynamic> j) => CommunityComment(
        id: (j['id'] as num).toInt(),
        body: j['body'] as String? ?? '',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        nickname: j['nickname'] as String? ?? 'loper',
        mine: j['mine'] == true,
        canDelete: j['can_delete'] == true,
      );
}

/// De community komt via databasefuncties (migratie 0033); die controleren lidmaatschap, regels en limieten.
class CommunityFeedService {
  CommunityFeedService(this._db);
  final SupabaseClient _db;

  Future<T> _rpc<T>(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await _db.rpc(fn, params: params) as T;
    } on PostgrestException catch (e) {
      // Functie bestaat nog niet: de migratie is nog niet gedraaid.
      if (e.code == 'PGRST202' || e.code == '42883') throw const CommunityNotReady();
      throw Exception(e.message);
    }
  }

  Future<List<CommunityPost>> feed({String? topic, int? before}) async {
    final rows = await _rpc<List<dynamic>>('community_feed', {'p_topic': topic, 'p_before': before, 'p_limit': 30});
    return [for (final r in rows) CommunityPost.fromJson((r as Map).cast<String, dynamic>())];
  }

  Future<List<CommunityComment>> comments(int postId) async {
    final rows = await _rpc<List<dynamic>>('community_comments_of', {'p_post': postId});
    return [for (final r in rows) CommunityComment.fromJson((r as Map).cast<String, dynamic>())];
  }

  Future<bool> rulesAccepted() async => await _rpc<bool?>('community_rules_accepted') ?? false;
  Future<void> acceptRules() => _rpc<dynamic>('community_accept_rules');
  Future<void> post(String topic, String body) => _rpc<dynamic>('community_post', {'p_topic': topic, 'p_body': body});
  Future<void> comment(int postId, String body) => _rpc<dynamic>('community_comment', {'p_post': postId, 'p_body': body});
  Future<bool> like(int postId) async => await _rpc<bool?>('community_like', {'p_post': postId}) ?? false;
  Future<void> report(String kind, int id, String reason) =>
      _rpc<dynamic>('community_report', {'p_kind': kind, 'p_id': id, 'p_reason': reason});
  Future<void> delete(String kind, int id) => _rpc<dynamic>('community_delete', {'p_kind': kind, 'p_id': id});
  Future<void> block(String nickname) => _rpc<dynamic>('community_block', {'p_nickname': nickname});
}

/// De community staat nog niet aan (migratie 0033 niet gedraaid).
class CommunityNotReady implements Exception {
  const CommunityNotReady();
  @override
  String toString() => 'De community gaat binnenkort open.';
}

final communityFeedServiceProvider = Provider<CommunityFeedService>((ref) => CommunityFeedService(ref.watch(supabaseProvider)));

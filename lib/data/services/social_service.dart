import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import 'community_feed_service.dart' show CommunityComment, CommunityNotReady;

/// Wie een gedeelde run mag zien.
enum ShareVisibility {
  followers('followers', 'Volgers'),
  everyone('everyone', 'Iedereen');

  const ShareVisibility(this.key, this.label);
  final String key;
  final String label;

  static ShareVisibility of(String? k) => k == 'everyone' ? everyone : followers;
}

/// Hoe jij tegenover een andere loper staat.
enum FollowState {
  none,
  pending,
  accepted;

  static FollowState of(String? s) => switch (s) {
        'accepted' => accepted,
        'pending' => pending,
        _ => none,
      };
}

/// Een run die iemand met volgers of iedereen heeft gedeeld (een kopie, zonder hartslag en
/// met begin en eind van de route weggeknipt).
class SharedRun {
  const SharedRun({
    required this.id,
    required this.nickname,
    required this.title,
    required this.runDate,
    required this.distanceMeters,
    required this.movingTimeSeconds,
    required this.paceSecondsPerKm,
    this.elevationGainMeters,
    this.polyline,
    this.visibility = ShareVisibility.followers,
    required this.createdAt,
    this.kudos = 0,
    this.comments = 0,
    this.kudoed = false,
    this.mine = false,
    this.canDelete = false,
  });

  final int id;
  final String nickname;
  final String title;
  final DateTime runDate;
  final double distanceMeters;
  final int movingTimeSeconds;
  final double paceSecondsPerKm;
  final double? elevationGainMeters;
  final String? polyline;
  final ShareVisibility visibility;
  final DateTime createdAt;
  final int kudos;
  final int comments;
  final bool kudoed;
  final bool mine;
  final bool canDelete;

  bool get hasMap => (polyline ?? '').isNotEmpty;

  factory SharedRun.fromJson(Map<String, dynamic> j) => SharedRun(
        id: (j['id'] as num).toInt(),
        nickname: j['nickname'] as String? ?? 'loper',
        title: j['title'] as String? ?? 'Run',
        runDate: DateTime.tryParse(j['run_date'] as String? ?? '') ?? DateTime.now(),
        distanceMeters: (j['distance_meters'] as num?)?.toDouble() ?? 0,
        movingTimeSeconds: (j['moving_time_seconds'] as num?)?.toInt() ?? 0,
        paceSecondsPerKm: (j['pace_seconds_per_km'] as num?)?.toDouble() ?? 0,
        elevationGainMeters: (j['elevation_gain_meters'] as num?)?.toDouble(),
        polyline: j['polyline'] as String?,
        visibility: ShareVisibility.of(j['visibility'] as String?),
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        kudos: (j['kudos'] as num?)?.toInt() ?? 0,
        comments: (j['comments'] as num?)?.toInt() ?? 0,
        kudoed: j['kudoed'] == true,
        mine: j['mine'] == true,
        canDelete: j['can_delete'] == true,
      );

  SharedRun copyWith({int? kudos, bool? kudoed, int? comments}) => SharedRun(
        id: id,
        nickname: nickname,
        title: title,
        runDate: runDate,
        distanceMeters: distanceMeters,
        movingTimeSeconds: movingTimeSeconds,
        paceSecondsPerKm: paceSecondsPerKm,
        elevationGainMeters: elevationGainMeters,
        polyline: polyline,
        visibility: visibility,
        createdAt: createdAt,
        kudos: kudos ?? this.kudos,
        comments: comments ?? this.comments,
        kudoed: kudoed ?? this.kudoed,
        mine: mine,
        canDelete: canDelete,
      );
}

/// Profiel van een loper.
class RunnerProfile {
  const RunnerProfile({
    required this.nickname,
    this.isMe = false,
    this.approveFollowers = false,
    this.followers = 0,
    this.following = 0,
    this.runs = 0,
    this.state = FollowState.none,
    this.followsMe = false,
    this.canSeeRuns = true,
  });

  final String nickname;
  final bool isMe;
  final bool approveFollowers;
  final int followers;
  final int following;
  final int runs;
  final FollowState state;
  final bool followsMe;
  final bool canSeeRuns;

  factory RunnerProfile.fromJson(Map<String, dynamic> j) => RunnerProfile(
        nickname: j['nickname'] as String? ?? 'loper',
        isMe: j['is_me'] == true,
        approveFollowers: j['approve_followers'] == true,
        followers: (j['followers'] as num?)?.toInt() ?? 0,
        following: (j['following'] as num?)?.toInt() ?? 0,
        runs: (j['runs'] as num?)?.toInt() ?? 0,
        state: FollowState.of(j['follow_state'] as String?),
        followsMe: j['follows_me'] == true,
        canSeeRuns: j['can_see_runs'] != false,
      );
}

/// Extra's op een profiel (0038): bio, plaats, favoriete afstand en cijfers (alleen als je de runs mag zien).
class ProfileExtra {
  const ProfileExtra({this.bio, this.homeArea, this.favDistance, this.memberSince, this.yearKm, this.monthKm, this.monthSteps, this.photoHidden = false});
  final String? bio;
  final String? homeArea;

  /// '5k', '10k', 'half', 'marathon', 'trail' of 'ultra'.
  final String? favDistance;
  final DateTime? memberSince;
  final double? yearKm;
  final double? monthKm;
  final int? monthSteps;

  /// Alleen voor jezelf: je foto is na meldingen verborgen.
  final bool photoHidden;

  factory ProfileExtra.fromJson(Map<String, dynamic> j) => ProfileExtra(
        bio: j['bio'] as String?,
        homeArea: j['home_area'] as String?,
        favDistance: j['fav_distance'] as String?,
        memberSince: j['member_since'] == null ? null : DateTime.tryParse(j['member_since'] as String),
        yearKm: (j['year_km'] as num?)?.toDouble(),
        monthKm: (j['month_km'] as num?)?.toDouble(),
        monthSteps: (j['month_steps'] as num?)?.toInt(),
        photoHidden: j['photo_hidden'] == true,
      );
}

const favDistanceLabels = {
  '5k': '5 km',
  '10k': '10 km',
  'half': 'Halve marathon',
  'marathon': 'Marathon',
  'trail': 'Trail',
  'ultra': 'Ultra',
};

/// Plek op de stappenranglijst.
class StepEntry {
  const StepEntry({required this.nickname, required this.isMe, required this.steps, required this.rank});
  final String nickname;
  final bool isMe;
  final int steps;
  final int rank;

  factory StepEntry.fromJson(Map<String, dynamic> j) => StepEntry(
        nickname: j['nickname'] as String? ?? 'loper',
        isMe: j['is_me'] == true,
        steps: (j['steps'] as num?)?.toInt() ?? 0,
        rank: (j['rank'] as num?)?.toInt() ?? 0,
      );
}

/// Een loper in een lijst (volgers, volgend, verzoeken, zoeken).
class RunnerItem {
  const RunnerItem({required this.nickname, this.state = FollowState.none, this.followsMe = false});
  final String nickname;
  final FollowState state;
  final bool followsMe;

  factory RunnerItem.fromJson(Map<String, dynamic> j) => RunnerItem(
        nickname: j['nickname'] as String? ?? 'loper',
        state: FollowState.of(j['follow_state'] as String?),
        followsMe: j['follows_me'] == true,
      );
}

/// Jouw instellingen voor volgen.
class SocialSettings {
  const SocialSettings({required this.nickname, this.approveFollowers = false, this.requests = 0});
  final String nickname;
  final bool approveFollowers;
  final int requests;
}

/// Of en hoe een eigen run gedeeld is.
class MyShare {
  const MyShare({required this.id, required this.visibility, required this.title, this.kudos = 0, this.comments = 0});
  final int id;
  final ShareVisibility visibility;
  final String title;
  final int kudos;
  final int comments;
}

/// Volgen en runs delen via databasefuncties (migratie 0034). Die controleren lidmaatschap,
/// zichtbaarheid, blokkades en limieten; de app kan de tabellen zelf niet lezen.
class SocialService {
  SocialService(this._db);
  final SupabaseClient _db;

  Future<T> _rpc<T>(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await _db.rpc(fn, params: params) as T;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') throw const CommunityNotReady();
      throw Exception(e.message);
    }
  }

  List<Map<String, dynamic>> _rows(dynamic v) => [for (final r in (v as List? ?? const [])) (r as Map).cast<String, dynamic>()];

  Future<List<SharedRun>> feed({bool everyone = false, String? nickname, int? before}) async {
    final rows = await _rpc<dynamic>('social_feed', {
      'p_scope': everyone ? 'everyone' : 'following',
      'p_nickname': nickname,
      'p_before': before,
      'p_limit': 20,
    });
    return [for (final r in _rows(rows)) SharedRun.fromJson(r)];
  }

  Future<SocialSettings> settings() async {
    final rows = _rows(await _rpc<dynamic>('social_settings'));
    if (rows.isEmpty) throw Exception('Doe eerst mee met Samen (kies een bijnaam).');
    final r = rows.first;
    return SocialSettings(
      nickname: r['nickname'] as String? ?? '',
      approveFollowers: r['approve_followers'] == true,
      requests: (r['requests'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> setApprove(bool approve) => _rpc<dynamic>('social_set_approve', {'p_approve': approve});

  Future<FollowState> follow(String nickname) async =>
      FollowState.of(await _rpc<String?>('social_follow', {'p_nickname': nickname}));
  Future<void> unfollow(String nickname) => _rpc<dynamic>('social_unfollow', {'p_nickname': nickname});
  Future<void> answer(String nickname, {required bool accept}) =>
      _rpc<dynamic>('social_answer', {'p_nickname': nickname, 'p_accept': accept});
  Future<void> removeFollower(String nickname) => _rpc<dynamic>('social_remove_follower', {'p_nickname': nickname});

  /// [kind]: 'followers', 'following' of 'requests'.
  Future<List<RunnerItem>> people(String kind) async =>
      [for (final r in _rows(await _rpc<dynamic>('social_people', {'p_kind': kind}))) RunnerItem.fromJson(r)];

  Future<List<RunnerItem>> search(String query) async =>
      [for (final r in _rows(await _rpc<dynamic>('social_search', {'p_query': query}))) RunnerItem.fromJson(r)];

  Future<RunnerProfile> profile(String nickname) async {
    final rows = _rows(await _rpc<dynamic>('social_profile', {'p_nickname': nickname}));
    if (rows.isEmpty) throw Exception('Deze loper is niet gevonden.');
    return RunnerProfile.fromJson(rows.first);
  }

  Future<MyShare?> shareOf(String activityId) async {
    final rows = _rows(await _rpc<dynamic>('social_share_of', {'p_activity': activityId}));
    if (rows.isEmpty) return null;
    final r = rows.first;
    return MyShare(
      id: (r['id'] as num).toInt(),
      visibility: ShareVisibility.of(r['visibility'] as String?),
      title: r['title'] as String? ?? '',
      kudos: (r['kudos'] as num?)?.toInt() ?? 0,
      comments: (r['comments'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> shareRun(String activityId, {required ShareVisibility visibility, required String title, String? polyline}) =>
      _rpc<dynamic>('social_share_run', {
        'p_activity': activityId,
        'p_visibility': visibility.key,
        'p_title': title,
        'p_polyline': polyline,
      });

  Future<void> unshareRun(String activityId) => _rpc<dynamic>('social_unshare_run', {'p_activity': activityId});

  Future<bool> kudo(int shareId) async => await _rpc<bool?>('social_kudo', {'p_share': shareId}) ?? false;

  Future<List<String>> kudosOf(int shareId) async =>
      [for (final r in _rows(await _rpc<dynamic>('social_kudos_of', {'p_share': shareId}))) r['nickname'] as String? ?? ''];

  Future<List<CommunityComment>> comments(int shareId) async =>
      [for (final r in _rows(await _rpc<dynamic>('social_comments_of', {'p_share': shareId}))) CommunityComment.fromJson(r)];

  Future<void> comment(int shareId, String body) => _rpc<dynamic>('social_comment', {'p_share': shareId, 'p_body': body});

  /// [kind]: 'run' of 'run_comment'.
  Future<void> report(String kind, int id, String reason) =>
      _rpc<dynamic>('social_report', {'p_kind': kind, 'p_id': id, 'p_reason': reason});
  Future<void> delete(String kind, int id) => _rpc<dynamic>('social_delete', {'p_kind': kind, 'p_id': id});

  // ---- Profiel (0038) ----

  Future<ProfileExtra> profileExtra(String nickname) async {
    final rows = _rows(await _rpc<dynamic>('social_profile_extra', {'p_nickname': nickname}));
    return rows.isEmpty ? const ProfileExtra() : ProfileExtra.fromJson(rows.first);
  }

  Future<void> setProfile({String? bio, String? homeArea, String? favDistance}) =>
      _rpc<dynamic>('social_set_profile', {'p_bio': bio, 'p_area': homeArea, 'p_fav': favDistance});

  /// Zet een (al verkleinde) foto in de eigen map en legt hem vast. Geeft het pad terug.
  Future<String> uploadPhoto(Uint8List jpg) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw Exception('Log eerst in.');
    // Elke keer een nieuwe naam, zodat telefoons niet de oude foto uit hun cache blijven tonen.
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage.from('avatars').uploadBinary(path, jpg,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true, cacheControl: '604800'));
    final old = await _rpc<String?>('social_set_photo', {'p_path': path});
    if (old != null && old != path) _db.storage.from('avatars').remove([old]).ignore();
    return path;
  }

  Future<void> removePhoto() async {
    final old = await _rpc<String?>('social_set_photo', {'p_path': null});
    if (old != null) _db.storage.from('avatars').remove([old]).ignore();
  }

  /// Openbare link van een foto in de bucket `avatars`.
  String photoUrl(String path) => _db.storage.from('avatars').getPublicUrl(path);

  Future<void> reportProfile(String nickname, String reason) =>
      _rpc<dynamic>('social_report_profile', {'p_nickname': nickname, 'p_reason': reason});

  // ---- Stappenwedstrijd (0038) ----

  Future<void> submitSteps(DateTime month, int steps) => _rpc<dynamic>('steps_submit', {
        'p_month': '${month.year}-${month.month.toString().padLeft(2, '0')}-01',
        'p_steps': steps,
      });

  /// [scope]: 'friends' of 'group' (met [groupId]).
  Future<List<StepEntry>> stepsBoard(String scope, {int? groupId, DateTime? month}) async {
    final m = month ?? DateTime.now();
    return [
      for (final r in _rows(await _rpc<dynamic>('steps_board', {
        'p_scope': scope,
        'p_group': groupId,
        'p_month': '${m.year}-${m.month.toString().padLeft(2, '0')}-01',
      })))
        StepEntry.fromJson(r),
    ];
  }
}

final socialServiceProvider = Provider<SocialService>((ref) => SocialService(ref.watch(supabaseProvider)));

/// Aantal openstaande volgverzoeken (voor het stipje bij "Lopers"). 0 als je niet meedoet of het nog niet kan.
final followRequestCountProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    return (await ref.watch(socialServiceProvider).settings()).requests;
  } catch (_) {
    return 0;
  }
});

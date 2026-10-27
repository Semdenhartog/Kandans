import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/services/community_feed_service.dart';
import '../../data/services/community_service.dart';
import '../../shared/widgets.dart';
import '../challenges/community_screen.dart';
import '../../core/i18n.dart';

/// "Een uur geleden", "gisteren", of een datum.
String communityAgo(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inMinutes < 1) return 'net';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) return '${d.inHours} u';
  if (d.inDays == 1) return 'gisteren';
  if (d.inDays < 7) return '${d.inDays} d';
  return Fmt.date(t);
}

const _rules = [
  'Wees vriendelijk. Geen schelden, discriminatie of pesten.',
  'Alleen tekst: geen links, telefoonnummers of adressen.',
  'Deel geen locatie of tijden waarop je alleen loopt.',
  'Geen reclame of spam.',
  'Iets niet in orde? Meld het: na 3 meldingen verdwijnt het tot het bekeken is.',
];

/// Tabblad Community: berichten per onderwerp, reacties en duimpjes. Ranglijsten via de knop rechtsboven.
class CommunityFeedScreen extends ConsumerStatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  ConsumerState<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends ConsumerState<CommunityFeedScreen> {
  String? _topic;
  List<CommunityPost> _posts = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _end = false;
  Object? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _more();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  CommunityFeedService get _svc => ref.read(communityFeedServiceProvider);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _end = false;
    });
    try {
      final status = await ref.read(communityStatusProvider.future);
      if (!status.joined) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final list = await _svc.feed(topic: _topic);
      if (!mounted) return;
      setState(() {
        _posts = list;
        _end = list.length < 30;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _more() async {
    if (_loadingMore || _end || _posts.isEmpty) return;
    _loadingMore = true;
    try {
      final list = await _svc.feed(topic: _topic, before: _posts.last.id);
      if (mounted) {
        setState(() {
          _posts = [..._posts, ...list];
          _end = list.length < 30;
        });
      }
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  /// Huisregels één keer laten accepteren vóór het eerste bericht.
  Future<bool> _ensureRules() async {
    try {
      if (await _svc.rulesAccepted()) return true;
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
      return false;
    }
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Huisregels')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final r in _rules)
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: EdgeInsets.only(top: 6, right: 8), child: Icon(Icons.circle, size: 6, color: RwColors.accent)),
                Expanded(child: Text(tr(r), style: TextStyle(height: 1.35))),
              ]),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Later'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Akkoord'))),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await _svc.acceptRules();
      return true;
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
      return false;
    }
  }

  Future<void> _newPost() async {
    if (!await _ensureRules() || !mounted) return;
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Composer(initialTopic: _topic ?? 'algemeen'),
    );
    if (posted == true) {
      HapticFeedback.mediumImpact();
      _load();
    }
  }

  Future<void> _toggleLike(CommunityPost p) async {
    HapticFeedback.selectionClick();
    setState(() => _posts = [for (final x in _posts) x.id == p.id ? x.copyWith(liked: !p.liked, likes: p.likes + (p.liked ? -1 : 1)) : x]);
    try {
      await _svc.like(p.id);
    } catch (_) {
      if (mounted) setState(() => _posts = [for (final x in _posts) x.id == p.id ? p : x]);
    }
  }

  Future<void> _openThread(CommunityPost p) async {
    if (!await _ensureRules() || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Thread(post: p),
    );
    _load();
  }

  Future<void> _menu(CommunityPost p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (p.canDelete)
            ListTile(leading: Icon(Icons.delete_outline), title: Text(tr('Verwijderen')), onTap: () => Navigator.pop(ctx, 'delete')),
          if (!p.mine) ...[
            ListTile(leading: Icon(Icons.flag_outlined), title: Text(tr('Melden')), onTap: () => Navigator.pop(ctx, 'report')),
            ListTile(
              leading: Icon(Icons.block),
              title: Text('${p.nickname} blokkeren'),
              subtitle: Text(tr('Je ziet geen berichten meer van deze loper')),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
          ],
        ]),
      ),
    );
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case 'delete':
          await _svc.delete('post', p.id);
          if (mounted) showMessage(context, tr('Bericht verwijderd.'));
        case 'report':
          final reason = await _askReason(context);
          if (reason == null) return;
          await _svc.report('post', p.id, reason);
          if (mounted) showMessage(context, tr('Bedankt, we kijken ernaar.'));
        case 'block':
          await _svc.block(p.nickname);
          if (mounted) showMessage(context, 'Je ziet ${p.nickname} niet meer.');
      }
      _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(communityStatusProvider);
    final joined = status.value?.joined ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Community')),
        actions: [
          if (joined)
            IconButton(
              tooltip: tr('Nieuw bericht'),
              icon: const Icon(Icons.edit_square),
              onPressed: _newPost,
            ),
          IconButton(
            tooltip: tr('Ranglijsten en vrienden'),
            icon: Icon(Icons.leaderboard_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CommunityScreen()));
              ref.invalidate(communityStatusProvider);
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: joined && _error == null
          ? FloatingActionButton.extended(
              heroTag: 'community-new',
              onPressed: _newPost,
              icon: Icon(Icons.edit_outlined),
              label: Text(tr('Bericht')),
            )
          : null,
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
            children: [
              for (final e in [MapEntry<String?, String>(null, tr('Alles')), ...communityTopics.entries.map((e) => MapEntry<String?, String>(e.key, e.value))])
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tr(e.value)),
                    selected: _topic == e.key,
                    onSelected: (_) {
                      setState(() => _topic = e.key);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _body(joined)),
      ]),
    );
  }

  Widget _body(bool joined) {
    if (_loading) return LoadingView(cards: 3);
    if (_error is CommunityNotReady) {
      return EmptyState(
        icon: Icons.forum_outlined,
        title: tr('De community gaat binnenkort open'),
        message: tr('Hier praat je straks met andere lopers over routes, wedstrijden, schoenen en blessures, en spreek je af om samen te lopen.'),
        actionLabel: tr('Opnieuw proberen'),
        onAction: _load,
      );
    }
    if (_error != null) {
      return ErrorView(message: _error.toString().replaceFirst('Exception: ', ''), onRetry: _load);
    }
    if (!joined) {
      return EmptyState(
        icon: Icons.groups_outlined,
        title: tr('Praat mee met andere lopers'),
        message: tr('Kies een bijnaam en doe mee. Anderen zien alleen je bijnaam en wat je schrijft: geen runs, routes of locatie.'),
        actionLabel: tr('Meedoen'),
        onAction: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CommunityScreen()));
          ref.invalidate(communityStatusProvider);
          _load();
        },
      );
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(physics: AlwaysScrollableScrollPhysics(), children: [
          SizedBox(height: 40),
          EmptyState(
            icon: Icons.forum_outlined,
            title: _topic == null ? tr('Nog geen berichten') : 'Nog niets over ${communityTopics[_topic]!.toLowerCase()}',
            message: tr('Begin het gesprek: stel een vraag, deel een mooi rondje of zoek iemand om mee te lopen.'),
            actionLabel: tr('Eerste bericht'),
            onAction: _newPost,
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scroll,
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: _posts.length,
        separatorBuilder: (_, _) => SizedBox(height: 10),
        itemBuilder: (context, i) => _PostCard(
          post: _posts[i],
          onLike: () => _toggleLike(_posts[i]),
          onComments: () => _openThread(_posts[i]),
          onMenu: () => _menu(_posts[i]),
        ),
      ),
    );
  }
}

Future<String?> _askReason(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(tr('Waarom meld je dit?'), style: RwText.title.copyWith(fontSize: 20)),
          ),
          for (final r in [tr('Onvriendelijk of beledigend'), tr('Spam of reclame'), tr('Onveilig of persoonlijke gegevens'), tr('Iets anders')])
            ListTile(title: Text(r), onTap: () => Navigator.pop(ctx, r)),
        ]),
      ),
    );

class _Avatar extends StatelessWidget {
  const _Avatar(this.name, {this.size = 36});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [RwColors.accentLight, RwColors.accentDeep]),
        ),
        child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(color: RwColors.accentDark, fontWeight: FontWeight.w800, fontSize: size * 0.42)),
      );
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onLike, required this.onComments, required this.onMenu});
  final CommunityPost post;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final p = post;
    return RwCard(
      padding: EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Avatar(p.nickname),
          SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.nickname, style: TextStyle(fontWeight: FontWeight.w700)),
              Text('${tr(communityTopics[p.topic] ?? p.topic)} · ${communityAgo(p.createdAt)}',
                  style: TextStyle(color: RwColors.subtle, fontSize: 12)),
            ]),
          ),
          IconButton(tooltip: tr('Meer'), icon: Icon(Icons.more_horiz, color: RwColors.subtle), onPressed: onMenu),
        ]),
        Padding(
          padding: EdgeInsets.fromLTRB(0, 10, 8, 4),
          child: Text(p.body, style: TextStyle(fontSize: 15.5, height: 1.45)),
        ),
        Row(children: [
          TextButton.icon(
            onPressed: onLike,
            icon: Icon(p.liked ? Icons.thumb_up : Icons.thumb_up_outlined, size: 18, color: p.liked ? RwColors.accent : RwColors.muted),
            label: Text(p.likes == 0 ? tr('Duim') : '${p.likes}', style: TextStyle(color: p.liked ? RwColors.accent : RwColors.muted)),
          ),
          TextButton.icon(
            onPressed: onComments,
            icon: Icon(Icons.chat_bubble_outline, size: 18, color: RwColors.muted),
            label: Text(p.comments == 0 ? tr('Reageer') : '${p.comments}', style: TextStyle(color: RwColors.muted)),
          ),
        ]),
      ]),
    );
  }
}

/// Nieuw bericht: onderwerp kiezen en tekst.
class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.initialTopic});
  final String initialTopic;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  late String _topic = widget.initialTopic;
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await ref.read(communityFeedServiceProvider).post(_topic, _text.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Nieuw bericht'), style: RwText.title),
            SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in communityTopics.entries)
                ChoiceChip(label: Text(tr(e.value)), selected: _topic == e.key, onSelected: (_) => setState(() => _topic = e.key)),
            ]),
            SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: switch (_topic) {
                  'afspreken' => 'Bijv. "Wie loopt zaterdagochtend 10 km rond het Kootwijkerzand?"',
                  'blessures' => 'Bijv. "Last van mijn scheen na langere runs, iemand tips?"',
                  'spullen' => 'Bijv. "Welke schoen voor modderige bospaden?"',
                  _ => tr('Wat wil je delen of vragen?'),
                },
              ),
              onChanged: (_) => setState(() {}),
            ),
            FilledButton.icon(
              onPressed: _busy || _text.text.trim().length < 2 ? null : _send,
              icon: _busy ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.send),
              label: Text(tr('Plaatsen')),
            ),
            SizedBox(height: 6),
            Text(tr('Anderen zien je bijnaam en dit bericht. Deel geen adres, telefoonnummer of wanneer je alleen loopt.'),
                textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
          ]),
        ),
      );
}

/// Reacties onder een bericht.
class _Thread extends ConsumerStatefulWidget {
  const _Thread({required this.post});
  final CommunityPost post;

  @override
  ConsumerState<_Thread> createState() => _ThreadState();
}

class _ThreadState extends ConsumerState<_Thread> {
  List<CommunityComment>? _comments;
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await ref.read(communityFeedServiceProvider).comments(widget.post.id);
      if (mounted) setState(() => _comments = c);
    } catch (e) {
      if (mounted) setState(() => _comments = const []);
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await ref.read(communityFeedServiceProvider).comment(widget.post.id, _text.text.trim());
      _text.clear();
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commentMenu(CommunityComment c) async {
    final svc = ref.read(communityFeedServiceProvider);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (c.canDelete) ListTile(leading: Icon(Icons.delete_outline), title: Text(tr('Verwijderen')), onTap: () => Navigator.pop(ctx, 'delete')),
          if (!c.mine) ...[
            ListTile(leading: Icon(Icons.flag_outlined), title: Text(tr('Melden')), onTap: () => Navigator.pop(ctx, 'report')),
            ListTile(leading: Icon(Icons.block), title: Text('${c.nickname} blokkeren'), onTap: () => Navigator.pop(ctx, 'block')),
          ],
        ]),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'delete') await svc.delete('comment', c.id);
      if (action == 'report') {
        final reason = await _askReason(context);
        if (reason == null) return;
        await svc.report('comment', c.id, reason);
        if (mounted) showMessage(context, tr('Bedankt, we kijken ernaar.'));
      }
      if (action == 'block') await svc.block(c.nickname);
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final c = _comments;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Avatar(p.nickname, size: 30),
              SizedBox(width: 10),
              Expanded(child: Text(p.body, style: TextStyle(height: 1.4))),
            ]),
          ),
          Divider(height: 1),
          Flexible(
            child: c == null
                ? Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                : c.isEmpty
                    ? Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(tr('Nog geen reacties. Wees de eerste!'), textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted)),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.fromLTRB(20, 8, 8, 8),
                        children: [
                          for (final x in c)
                            Padding(
                              padding: EdgeInsets.only(bottom: 10),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _Avatar(x.nickname, size: 26),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${x.nickname} · ${communityAgo(x.createdAt)}', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
                                    SizedBox(height: 2),
                                    Text(x.body, style: TextStyle(height: 1.4)),
                                  ]),
                                ),
                                IconButton(
                                  tooltip: tr('Meer'),
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(Icons.more_horiz, size: 18, color: RwColors.subtle),
                                  onPressed: () => _commentMenu(x),
                                ),
                              ]),
                            ),
                        ],
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: tr('Reageer…'), counterText: ''),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  tooltip: tr('Versturen'),
                  onPressed: _busy || _text.text.trim().isEmpty ? null : _send,
                  icon: Icon(Icons.send, color: RwColors.accent),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

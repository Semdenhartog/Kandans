import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/social_service.dart';
import '../../shared/widgets.dart';
import 'community_feed_screen.dart' show RunnerAvatar;
import 'runner_profile_screen.dart';

/// [tab]: 0 = zoeken en verzoeken, 1 = volgers, 2 = volgend.
void openPeople(BuildContext context, {int tab = 0}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PeopleScreen(initialTab: tab)));

/// Lopers: zoeken op bijnaam, volgverzoeken, je volgers en wie je volgt.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  SocialSettings? _settings;
  List<RunnerItem> _requests = const [];
  List<RunnerItem> _followers = const [];
  List<RunnerItem> _following = const [];
  List<RunnerItem>? _results;
  final _query = TextEditingController();
  Timer? _debounce;
  Object? _error;
  bool _loading = true;

  SocialService get _svc => ref.read(socialServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _svc.settings();
      final lists = await Future.wait([_svc.people('requests'), _svc.people('followers'), _svc.people('following')]);
      if (!mounted) return;
      setState(() {
        _settings = s;
        _requests = lists[0];
        _followers = lists[1];
        _following = lists[2];
        _error = null;
        _loading = false;
      });
      ref.invalidate(followRequestCountProvider);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _search(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await _svc.search(q.trim());
        if (mounted && _query.text.trim() == q.trim()) setState(() => _results = r);
      } catch (_) {}
    });
  }

  Future<void> _act(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      if (mounted && done != null) showMessage(context, done);
      await _load();
      if (_query.text.trim().length >= 2) _search(_query.text);
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _setApprove(bool v) async {
    if (!v && _requests.isNotEmpty) {
      final ok = await confirmDialog(
        context,
        title: tr('Goedkeuren uitzetten?'),
        message: trf('De {n} openstaande verzoeken worden dan meteen goedgekeurd.', {'n': _requests.length}),
        confirmLabel: tr('Uitzetten'),
        destructive: false,
      );
      if (!ok) return;
    }
    await _act(() => _svc.setApprove(v));
  }

  /// Knoppen in een lijstregel: niet over de volle breedte (zoals de app-stijl standaard doet).
  static final _small = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, 38)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
    visualDensity: VisualDensity.compact,
  );

  Widget _followButton(RunnerItem p) => switch (p.state) {
        FollowState.none => FilledButton.tonal(
            style: _small,
            onPressed: () => _act(() async {
              final s = await _svc.follow(p.nickname);
              if (s == FollowState.pending && mounted) {
                showMessage(context, trf('Verzoek verstuurd. {naam} keurt volgers zelf goed.', {'naam': p.nickname}));
              }
            }),
            child: Text(p.followsMe ? tr('Terugvolgen') : tr('Volgen')),
          ),
        FollowState.pending => OutlinedButton(style: _small, onPressed: () => _act(() => _svc.unfollow(p.nickname)), child: Text(tr('Aangevraagd'))),
        FollowState.accepted => OutlinedButton(style: _small, onPressed: () => _act(() => _svc.unfollow(p.nickname)), child: Text(tr('Volgend'))),
      };

  Widget _tile(RunnerItem p, {Widget? trailing, String? subtitle}) => ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        leading: RunnerAvatar(p.nickname),
        title: Text(p.nickname, style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
        trailing: trailing ?? _followButton(p),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RunnerProfileScreen(nickname: p.nickname)));
          _load();
        },
      );

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Lopers')),
          actions: [
            if (_settings != null)
              IconButton(
                tooltip: tr('Mijn profiel'),
                icon: Icon(Icons.account_circle_outlined),
                onPressed: () => openRunnerProfile(context, _settings!.nickname),
              ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: _requests.isEmpty ? tr('Zoeken') : '${tr('Zoeken')} · ${_requests.length}'),
            Tab(text: '${tr('Volgers')} ${_followers.length}'),
            Tab(text: '${tr('Volgend')} ${_following.length}'),
          ]),
        ),
        body: _loading
            ? LoadingView(cards: 2)
            : _error != null
                ? ErrorView(message: _error.toString().replaceFirst('Exception: ', ''), onRetry: _load)
                : TabBarView(children: [_searchTab(), _followersTab(), _followingTab()]),
      ),
    );
  }

  Widget _searchTab() => ListView(padding: EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: tr('Zoek een loper op bijnaam')),
            onChanged: _search,
          ),
        ),
        if (_results != null) ...[
          if (_results!.isEmpty)
            Padding(
              padding: EdgeInsets.all(24),
              child: Text(tr('Niemand gevonden met deze bijnaam.'), textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted)),
            ),
          for (final p in _results!) _tile(p, subtitle: p.followsMe ? tr('Volgt jou') : null),
        ] else ...[
          if (_requests.isNotEmpty) ...[
            Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(tr('VOLGVERZOEKEN'), style: RwText.overline)),
            for (final p in _requests)
              _tile(
                p,
                subtitle: tr('Wil je volgen'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: tr('Weigeren'),
                    icon: Icon(Icons.close, color: RwColors.subtle),
                    onPressed: () => _act(() => _svc.answer(p.nickname, accept: false)),
                  ),
                  FilledButton(
                    style: _small,
                    onPressed: () => _act(() => _svc.answer(p.nickname, accept: true), done: trf('{naam} volgt je nu.', {'naam': p.nickname})),
                    child: Text(tr('Goedkeuren')),
                  ),
                ]),
              ),
            Divider(height: 24),
          ],
          Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text(tr('PRIVACY'), style: RwText.overline)),
          SwitchListTile(
            value: _settings?.approveFollowers ?? false,
            onChanged: _setApprove,
            title: Text(tr('Volgers zelf goedkeuren')),
            subtitle: Text(tr('Aan: wie je wil volgen, stuurt eerst een verzoek. Je runs voor "iedereen" zien dan ook alleen je volgers.')),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              tr('Anderen zien alleen je bijnaam. Je deelt een run pas als je dat zelf kiest, zonder hartslag en zonder begin en eind van je route.'),
              style: TextStyle(color: RwColors.subtle, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ]);

  Widget _followersTab() => _followers.isEmpty
      ? EmptyState(
          icon: Icons.group_outlined,
          title: tr('Nog geen volgers'),
          message: tr('Deel je vriendcode of uitnodiging via Ranglijsten en vrienden, of deel je eerste run.'),
        )
      : ListView(padding: EdgeInsets.only(top: 8, bottom: 32), children: [
          for (final p in _followers)
            _tile(
              p,
              trailing: PopupMenuButton<String>(
                tooltip: tr('Meer'),
                onSelected: (v) {
                  if (v == 'remove') _act(() => _svc.removeFollower(p.nickname), done: trf('{naam} volgt je niet meer.', {'naam': p.nickname}));
                  if (v == 'follow') _act(() => _svc.follow(p.nickname));
                },
                itemBuilder: (_) => [
                  if (p.state == FollowState.none) PopupMenuItem(value: 'follow', child: Text(tr('Terugvolgen'))),
                  PopupMenuItem(value: 'remove', child: Text(tr('Weghalen als volger'))),
                ],
              ),
            ),
        ]);

  Widget _followingTab() => _following.isEmpty
      ? EmptyState(
          icon: Icons.person_search_outlined,
          title: tr('Je volgt nog niemand'),
          message: tr('Zoek lopers op bijnaam, of tik in de feed op iemands naam.'),
        )
      : ListView(padding: EdgeInsets.only(top: 8, bottom: 32), children: [
          for (final p in _following) _tile(p, subtitle: p.followsMe ? tr('Volgt jou') : null),
        ]);
}

/// Zoals [openPeople], maar wacht tot het scherm weer dicht is.
Future<void> openPeopleAndWait(BuildContext context, {int tab = 0}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PeopleScreen(initialTab: tab)));

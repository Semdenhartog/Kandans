import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/social_service.dart';
import '../../shared/widgets.dart';
import 'community_feed_screen.dart' show RunnerAvatar;
import 'people_screen.dart';
import 'shared_run_card.dart';

void openRunnerProfile(BuildContext context, String nickname) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RunnerProfileScreen(nickname: nickname)));

/// Profiel van een loper: aantallen, volgen en de runs die jij mag zien.
class RunnerProfileScreen extends ConsumerStatefulWidget {
  const RunnerProfileScreen({super.key, required this.nickname});
  final String nickname;

  @override
  ConsumerState<RunnerProfileScreen> createState() => _RunnerProfileScreenState();
}

class _RunnerProfileScreenState extends ConsumerState<RunnerProfileScreen> {
  RunnerProfile? _profile;
  List<SharedRun> _runs = const [];
  Object? _error;
  bool _loading = true;
  bool _busy = false;

  SocialService get _svc => ref.read(socialServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _svc.profile(widget.nickname);
      final runs = p.canSeeRuns ? await _svc.feed(nickname: p.nickname) : const <SharedRun>[];
      if (!mounted) return;
      setState(() {
        _profile = p;
        _runs = runs;
        _error = null;
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

  Future<void> _toggleFollow() async {
    final p = _profile;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      if (p.state == FollowState.none) {
        HapticFeedback.mediumImpact();
        final s = await _svc.follow(p.nickname);
        if (mounted && s == FollowState.pending) {
          showMessage(context, trf('Verzoek verstuurd. {naam} keurt volgers zelf goed.', {'naam': p.nickname}));
        }
      } else {
        final ok = p.state == FollowState.pending ||
            await confirmDialog(context,
                title: trf('{naam} niet meer volgen?', {'naam': p.nickname}),
                message: tr('Je ziet de runs dan niet meer in je feed.'),
                confirmLabel: tr('Ontvolgen'));
        if (!ok) return;
        await _svc.unfollow(p.nickname);
      }
      ref.invalidate(followRequestCountProvider);
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _replace(SharedRun r) => setState(() => _runs = [for (final x in _runs) x.id == r.id ? r : x]);

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      appBar: AppBar(title: Text(p?.nickname ?? widget.nickname)),
      body: _loading
          ? LoadingView(cards: 2)
          : _error != null || p == null
              ? ErrorView(message: (_error ?? '').toString().replaceFirst('Exception: ', ''), onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _header(p),
                      SizedBox(height: 18),
                      if (!p.canSeeRuns)
                        EmptyState(
                          icon: Icons.lock_outline,
                          title: tr('Alleen voor volgers'),
                          message: trf('{naam} keurt volgers zelf goed. Stuur een verzoek om de runs te zien.', {'naam': p.nickname}),
                        )
                      else if (_runs.isEmpty)
                        EmptyState(
                          icon: Icons.directions_run,
                          title: tr('Nog geen gedeelde runs'),
                          message: p.isMe
                              ? tr('Deel een run vanuit je runs: open een run en kies "Delen met volgers".')
                              : trf('{naam} heeft nog niets gedeeld dat jij kunt zien.', {'naam': p.nickname}),
                        )
                      else
                        for (final r in _runs)
                          Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: SharedRunCard(
                              run: r,
                              showName: false,
                              onKudo: () => SharedRunActions(context, ref).kudo(r, _replace),
                              onKudosList: () => SharedRunActions(context, ref).kudosList(r),
                              onComments: () async {
                                if (await SharedRunActions(context, ref).comments(r)) _load();
                              },
                              onMenu: () async {
                                if (await SharedRunActions(context, ref).menu(r)) {
                                  if (!mounted) return;
                                  // Geblokkeerd: dit profiel bestaat voor jou niet meer.
                                  RunnerProfile? p2;
                                  try {
                                    p2 = await _svc.profile(widget.nickname);
                                  } catch (_) {}
                                  if (!mounted) return;
                                  if (p2 == null) {
                                    Navigator.of(context).pop();
                                  } else {
                                    _load();
                                  }
                                }
                              },
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }

  Widget _header(RunnerProfile p) => RwCard(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            RunnerAvatar(p.nickname, size: 64),
            SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.nickname, style: RwText.title),
                if (p.followsMe && !p.isMe)
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(tr('Volgt jou'), style: TextStyle(color: RwColors.subtle, fontSize: 13)),
                  ),
                if (p.approveFollowers)
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Icon(Icons.lock_outline, size: 14, color: RwColors.subtle),
                      SizedBox(width: 4),
                      Flexible(child: Text(tr('Keurt volgers zelf goed'), style: TextStyle(color: RwColors.subtle, fontSize: 13))),
                    ]),
                  ),
              ]),
            ),
          ]),
          SizedBox(height: 16),
          Row(children: [
            _Count(value: p.runs, label: tr('Runs')),
            _Count(value: p.followers, label: tr('Volgers'), onTap: p.isMe ? () => openPeople(context, tab: 1) : null),
            _Count(value: p.following, label: tr('Volgend'), onTap: p.isMe ? () => openPeople(context, tab: 2) : null),
          ]),
          if (!p.isMe) ...[
            SizedBox(height: 16),
            p.state == FollowState.none
                ? FilledButton.icon(
                    onPressed: _busy ? null : _toggleFollow,
                    icon: Icon(Icons.person_add_alt_1),
                    label: Text(p.followsMe ? tr('Terugvolgen') : tr('Volgen')),
                  )
                : OutlinedButton.icon(
                    onPressed: _busy ? null : _toggleFollow,
                    icon: Icon(p.state == FollowState.pending ? Icons.schedule : Icons.check),
                    label: Text(p.state == FollowState.pending ? tr('Verzoek verstuurd') : tr('Volgend')),
                  ),
          ],
        ]),
      );
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label, this.onTap});
  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Text('$value', style: RwText.number.copyWith(fontSize: 24)),
              SizedBox(height: 2),
              Text(label, style: RwText.label),
            ]),
          ),
        ),
      );
}

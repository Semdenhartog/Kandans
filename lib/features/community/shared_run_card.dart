import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/community_feed_service.dart';
import '../../data/services/social_service.dart';
import '../../shared/widgets.dart';
import '../routes/route_map.dart';
import '../routes/route_shape.dart';
import 'community_feed_screen.dart' show RunnerAvatar, askReportReason, communityAgo, ensureCommunityRules;
import 'runner_profile_screen.dart';

/// Een gedeelde run in de feed of op een profiel.
class SharedRunCard extends StatelessWidget {
  const SharedRunCard({
    super.key,
    required this.run,
    required this.onKudo,
    required this.onComments,
    required this.onMenu,
    this.onKudosList,
    this.showName = true,
  });

  final SharedRun run;
  final VoidCallback onKudo;
  final VoidCallback onComments;
  final VoidCallback onMenu;

  /// Tik op het aantal: wie gaf applaus.
  final VoidCallback? onKudosList;

  /// Op een profiel staat de naam al bovenaan.
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final r = run;
    return RwCard(
      padding: EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (showName) ...[
            InkWell(
              borderRadius: BorderRadius.circular(RwRadius.m),
              onTap: () => openRunnerProfile(context, r.nickname),
              child: RunnerAvatar(r.nickname),
            ),
            SizedBox(width: 10),
          ],
          Expanded(
            child: InkWell(
              onTap: showName ? () => openRunnerProfile(context, r.nickname) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (showName) Text(r.nickname, style: TextStyle(fontWeight: FontWeight.w700)),
                Row(children: [
                  Flexible(
                    child: Text('${Fmt.date(r.runDate)} · ${communityAgo(r.createdAt)}',
                        overflow: TextOverflow.ellipsis, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
                  ),
                  if (r.mine) ...[
                    SizedBox(width: 6),
                    Icon(r.visibility == ShareVisibility.everyone ? Icons.public : Icons.group_outlined, size: 13, color: RwColors.subtle),
                  ],
                ]),
              ]),
            ),
          ),
          IconButton(tooltip: tr('Meer'), icon: Icon(Icons.more_horiz, color: RwColors.subtle), onPressed: onMenu),
        ]),
        Padding(
          padding: EdgeInsets.fromLTRB(0, 10, 8, 10),
          child: Text(r.title, style: TextStyle(fontFamily: RwFonts.display, fontSize: 19, fontWeight: FontWeight.w700, height: 1.2)),
        ),
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: Wrap(spacing: 22, runSpacing: 8, children: [
            _Stat(label: tr('Afstand'), value: Fmt.km(r.distanceMeters)),
            _Stat(label: tr('Tijd'), value: Fmt.duration(r.movingTimeSeconds)),
            _Stat(label: tr('Tempo'), value: Fmt.pace(r.paceSecondsPerKm)),
            if ((r.elevationGainMeters ?? 0) >= 1) _Stat(label: tr('Hoogte'), value: '${r.elevationGainMeters!.round()} m'),
          ]),
        ),
        if (r.hasMap)
          Padding(
            padding: EdgeInsets.fromLTRB(0, 12, 8, 0),
            child: Semantics(
              button: true,
              label: tr('Route op de kaart bekijken'),
              child: GestureDetector(
                onTap: () => _openMap(context, r),
                // Dubbel tikken op de route = applaus (zoals een hartje op Instagram).
                onDoubleTap: r.mine || r.kudoed ? null : onKudo,
                child: Container(
                  height: 150,
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: RwColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(RwRadius.m),
                    border: Border.all(color: RwColors.hairline),
                  ),
                  child: ExcludeSemantics(child: RouteShape(polyline: r.polyline!, strokeWidth: 2.5)),
                ),
              ),
            ),
          ),
        SizedBox(height: 4),
        Row(children: [
          TextButton.icon(
            onPressed: r.mine ? (r.kudos > 0 ? onKudosList : null) : onKudo,
            // Kleine "pop" bij applaus geven (punt 41).
            icon: TweenAnimationBuilder<double>(
              key: ValueKey(r.kudoed),
              tween: Tween(begin: r.kudoed ? 1.7 : 1.0, end: 1.0),
              duration: const Duration(milliseconds: 450),
              curve: Curves.elasticOut,
              builder: (_, s, child) => Transform.scale(scale: s, child: child),
              child: Icon(r.kudoed ? Icons.celebration : Icons.celebration_outlined, size: 18, color: r.kudoed ? RwColors.accent : RwColors.muted),
            ),
            label: Text(r.kudos == 0 ? tr('Applaus') : '${r.kudos}', style: TextStyle(color: r.kudoed ? RwColors.accent : RwColors.muted)),
          ),
          TextButton.icon(
            onPressed: onComments,
            icon: Icon(Icons.chat_bubble_outline, size: 18, color: RwColors.muted),
            label: Text(r.comments == 0 ? tr('Reageer') : '${r.comments}', style: TextStyle(color: RwColors.muted)),
          ),
          if (!r.mine && r.kudos > 0 && onKudosList != null) ...[
            Spacer(),
            TextButton(onPressed: onKudosList, child: Text(tr('Wie?'), style: TextStyle(color: RwColors.subtle, fontSize: 12))),
          ],
        ]),
      ]),
    );
  }

  static void _openMap(BuildContext context, SharedRun r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.7,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('${r.title} · ${Fmt.km(r.distanceMeters, decimals: 1)}', style: RwText.title.copyWith(fontSize: 20)),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: RouteMap(polyline: r.polyline!, showLegend: false, compact: true),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr('Begin en eind van de route zijn verborgen.'),
                  textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: RwText.label),
        SizedBox(height: 2),
        Text(value, style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 17, fontWeight: FontWeight.w700)),
      ]);
}

/// Acties op gedeelde runs, gedeeld door de feed en het profiel.
/// Elke actie geeft de bijgewerkte run terug, of null als de lijst opnieuw geladen moet worden.
class SharedRunActions {
  SharedRunActions(this.context, this.ref);
  final BuildContext context;
  final WidgetRef ref;

  SocialService get _svc => ref.read(socialServiceProvider);

  void _error(Object e) {
    if (context.mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
  }

  /// Applaus geven of terugnemen. [update] krijgt meteen de nieuwe stand (en bij een fout de oude terug).
  Future<void> kudo(SharedRun r, void Function(SharedRun) update) async {
    if (r.mine) return;
    HapticFeedback.selectionClick();
    update(r.copyWith(kudoed: !r.kudoed, kudos: r.kudos + (r.kudoed ? -1 : 1)));
    try {
      await _svc.kudo(r.id);
    } catch (e) {
      update(r);
      _error(e);
    }
  }

  Future<void> kudosList(SharedRun r) async {
    List<String> names;
    try {
      names = await _svc.kudosOf(r.id);
    } catch (e) {
      _error(e);
      return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.6),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr('Applaus van'), style: RwText.title.copyWith(fontSize: 20)),
            ),
            for (final n in names)
              ListTile(
                leading: RunnerAvatar(n, size: 32),
                title: Text(n),
                onTap: () {
                  Navigator.pop(ctx);
                  openRunnerProfile(context, n);
                },
              ),
          ]),
        ),
      ),
    );
  }

  /// Reacties openen. Geeft true als de lijst opnieuw geladen moet worden.
  Future<bool> comments(SharedRun r) async {
    if (!await ensureCommunityRules(context, ref) || !context.mounted) return false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RunThread(run: r),
    );
    return true;
  }

  /// Menu (verwijderen, melden, blokkeren). Geeft true als de lijst opnieuw geladen moet worden.
  Future<bool> menu(SharedRun r) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (r.canDelete)
            ListTile(
              leading: Icon(Icons.visibility_off_outlined),
              title: Text(r.mine ? tr('Niet meer delen') : tr('Verwijderen')),
              subtitle: r.mine ? Text(tr('De run blijft gewoon bij jouw runs staan')) : null,
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          if (!r.mine) ...[
            ListTile(leading: Icon(Icons.person_outline), title: Text(tr('Profiel bekijken')), onTap: () => Navigator.pop(ctx, 'profile')),
            ListTile(leading: Icon(Icons.flag_outlined), title: Text(tr('Melden')), onTap: () => Navigator.pop(ctx, 'report')),
            ListTile(
              leading: Icon(Icons.block),
              title: Text(trf('{naam} blokkeren', {'naam': r.nickname})),
              subtitle: Text(tr('Jullie volgen elkaar dan niet meer en zien elkaars runs niet')),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
          ],
        ]),
      ),
    );
    if (action == null || !context.mounted) return false;
    try {
      switch (action) {
        case 'profile':
          openRunnerProfile(context, r.nickname);
          return false;
        case 'delete':
          await _svc.delete('run', r.id);
          if (context.mounted) showMessage(context, r.mine ? tr('Je deelt deze run niet meer.') : tr('Run verwijderd.'));
        case 'report':
          final reason = await askReportReason(context);
          if (reason == null) return false;
          await _svc.report('run', r.id, reason);
          if (context.mounted) showMessage(context, tr('Bedankt, we kijken ernaar.'));
        case 'block':
          await ref.read(communityFeedServiceProvider).block(r.nickname);
          if (context.mounted) showMessage(context, trf('Je ziet {naam} niet meer.', {'naam': r.nickname}));
      }
      return true;
    } catch (e) {
      _error(e);
      return false;
    }
  }
}

/// Reacties onder een gedeelde run.
class _RunThread extends ConsumerStatefulWidget {
  const _RunThread({required this.run});
  final SharedRun run;

  @override
  ConsumerState<_RunThread> createState() => _RunThreadState();
}

class _RunThreadState extends ConsumerState<_RunThread> {
  List<CommunityComment>? _comments;
  final _text = TextEditingController();
  bool _busy = false;

  SocialService get _svc => ref.read(socialServiceProvider);

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
      final c = await _svc.comments(widget.run.id);
      if (mounted) setState(() => _comments = c);
    } catch (_) {
      if (mounted) setState(() => _comments = const []);
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await _svc.comment(widget.run.id, _text.text.trim());
      _text.clear();
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _react(CommunityComment c, String emoji) async {
    final list = _comments;
    if (list == null) return;
    // Meteen tonen, daarna pas naar de server.
    setState(() => _comments = [for (final x in list) x.id == c.id ? x.toggled(emoji) : x]);
    try {
      await _svc.react(c.id, emoji);
    } catch (e) {
      if (mounted) {
        setState(() => _comments = list);
        showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
      }
    }
  }

  /// Bijnamen die je met @ kunt noemen: de loper van de run en wie al reageerde.
  List<String> get _mentionable {
    final names = <String>{widget.run.nickname, for (final x in _comments ?? const <CommunityComment>[]) if (!x.mine) x.nickname};
    return names.where((n) => n.isNotEmpty).toList();
  }

  /// Het woord met @ waar de cursor nu staat, of null.
  String? get _typingMention {
    final t = _text.text;
    final pos = _text.selection.baseOffset < 0 ? t.length : _text.selection.baseOffset;
    final before = t.substring(0, pos.clamp(0, t.length));
    final m = RegExp(r'@([A-Za-z0-9_.\-]{0,30})$').firstMatch(before);
    return m?.group(1);
  }

  void _insertMention(String name) {
    final t = _text.text;
    final pos = _text.selection.baseOffset < 0 ? t.length : _text.selection.baseOffset.clamp(0, t.length);
    final start = t.substring(0, pos).lastIndexOf('@');
    if (start < 0) return;
    final next = '${t.substring(0, start)}@$name ${t.substring(pos)}';
    _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + name.length + 2));
    setState(() {});
  }

  Future<void> _quickSend(String emoji) async {
    _text.text = emoji;
    await _send();
  }

  Future<void> _commentMenu(CommunityComment c) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (c.canDelete) ListTile(leading: Icon(Icons.delete_outline), title: Text(tr('Verwijderen')), onTap: () => Navigator.pop(ctx, 'delete')),
          if (!c.mine) ...[
            ListTile(leading: Icon(Icons.flag_outlined), title: Text(tr('Melden')), onTap: () => Navigator.pop(ctx, 'report')),
            ListTile(leading: Icon(Icons.block), title: Text(trf('{naam} blokkeren', {'naam': c.nickname})), onTap: () => Navigator.pop(ctx, 'block')),
          ],
        ]),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'delete') await _svc.delete('run_comment', c.id);
      if (action == 'report') {
        final reason = await askReportReason(context);
        if (reason == null) return;
        await _svc.report('run_comment', c.id, reason);
        if (mounted) showMessage(context, tr('Bedankt, we kijken ernaar.'));
      }
      if (action == 'block') await ref.read(communityFeedServiceProvider).block(c.nickname);
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.run;
    final c = _comments;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(children: [
              RunnerAvatar(r.nickname, size: 30),
              SizedBox(width: 10),
              Expanded(
                child: Text('${r.title} · ${Fmt.km(r.distanceMeters, decimals: 1)}',
                    style: TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
              ),
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
                                RunnerAvatar(x.nickname, size: 26),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${x.nickname} · ${communityAgo(x.createdAt)}', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
                                    SizedBox(height: 2),
                                    MentionText(x.body),
                                    SizedBox(height: 4),
                                    _ReactionRow(comment: x, onToggle: (e) => _react(x, e)),
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
          Builder(builder: (context) {
            final typing = _typingMention;
            if (typing == null) {
              if (_text.text.isNotEmpty) return SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Row(children: [
                  for (final e in CommunityComment.quickReactions)
                    Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(e, style: TextStyle(fontSize: 18)),
                        tooltip: tr('Snel reageren'),
                        onPressed: _busy ? null : () => _quickSend(e),
                      ),
                    ),
                ]),
              );
            }
            final options = [
              for (final n in _mentionable)
                if (n.toLowerCase().startsWith(typing.toLowerCase())) n,
            ];
            if (options.isEmpty) return SizedBox.shrink();
            return SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                children: [
                  for (final n in options)
                    Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: RunnerAvatar(n, size: 20),
                        label: Text('@$n'),
                        onPressed: () => _insertMention(n),
                      ),
                    ),
                ],
              ),
            );
          }),
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
                    decoration: InputDecoration(hintText: tr('Reageer… (noem iemand met @)'), counterText: ''),
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

/// Snelle reacties onder een reactie: 👏 🔥 💪 met aantallen; tik = aan/uit.
class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.comment, required this.onToggle});
  final CommunityComment comment;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, children: [
      for (final e in CommunityComment.quickReactions)
        Semantics(
          button: true,
          selected: comment.myReactions.contains(e),
          label: trf('{emoji} reactie, {n} keer', {'emoji': e, 'n': '${comment.reactions[e] ?? 0}'}),
          child: InkWell(
            borderRadius: BorderRadius.circular(RwRadius.s),
            onTap: () => onToggle(e),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(RwRadius.s),
                color: comment.myReactions.contains(e) ? RwColors.accent.withValues(alpha: 0.16) : Colors.transparent,
                border: Border.all(color: comment.myReactions.contains(e) ? RwColors.accent : RwColors.border),
              ),
              child: Text(
                (comment.reactions[e] ?? 0) > 0 ? '$e ${comment.reactions[e]}' : e,
                style: TextStyle(fontSize: 13, color: RwColors.muted),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Tekst waarin @bijnamen goud en vet staan.
class MentionText extends StatelessWidget {
  const MentionText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(TextStyle(height: 1.4));
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in mentionPattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(0), style: TextStyle(color: RwColors.accent, fontWeight: FontWeight.w700)));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

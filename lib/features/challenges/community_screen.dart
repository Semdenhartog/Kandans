import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../data/services/community_service.dart';
import '../../shared/widgets.dart';
import 'challenges.dart' show challengeGold;

void openCommunity(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CommunityScreen()));

/// Ranglijst per (ranglijst, alleen vrienden).
final communityBoardProvider = FutureProvider.autoDispose.family<BoardResult, (String, bool)>(
  (ref, a) => ref.watch(communityServiceProvider).board(a.$1, friends: a.$2),
);

const _joinedKey = 'community_joined';

/// Na het opslaan van een run: standen bijwerken, alleen als je meedoet. Fouten stil negeren.
Future<void> refreshCommunityQuietly(CommunityService service) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_joinedKey) != true) return;
    await service.refresh();
  } catch (_) {}
}

Future<void> _rememberJoined(bool joined) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_joinedKey, joined);
  } catch (_) {}
}

/// "Samen": ranglijsten met andere lopers (alleen bijnaam en totaal).
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key, this.refreshOnOpen = true});

  /// Uit in schermafbeeldingen-tests.
  final bool refreshOnOpen;

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  String? _board;
  bool _friends = false;
  bool _busy = false;
  bool _refreshed = false;
  final _nickname = TextEditingController();

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _refreshOnce() async {
    if (_refreshed || !widget.refreshOnOpen) return;
    _refreshed = true;
    await _rememberJoined(true);
    try {
      await ref.read(communityServiceProvider).refresh();
      ref.invalidate(communityBoardProvider);
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() => _run(() async {
        await ref.read(communityServiceProvider).join(_nickname.text.trim());
        await _rememberJoined(true);
        _refreshed = true; // meedoen rekent je standen al uit
        ref.invalidate(communityStatusProvider);
        ref.invalidate(communityBoardProvider);
        HapticFeedback.mediumImpact();
        if (mounted) showMessage(context, 'Je staat op de ranglijsten. Succes!');
      });

  Future<void> _leave() async {
    final ok = await confirmDialog(context,
        title: 'Stoppen met Samen?',
        message: 'Je bijnaam, je standen en je vrienden worden verwijderd. Je runs blijven gewoon in de app.',
        confirmLabel: 'Stoppen');
    if (!ok) return;
    await _run(() async {
      await ref.read(communityServiceProvider).leave();
      await _rememberJoined(false);
      ref.invalidate(communityStatusProvider);
    });
  }

  Future<void> _addFriend() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RwColors.surface,
        title: const Text('Vriend toevoegen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Vriendcode', hintText: 'Bijv. K7QX2M'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Toevoegen'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (code == null || code.trim().isEmpty) return;
    await _run(() async {
      final name = await ref.read(communityServiceProvider).follow(code);
      ref.invalidate(communityBoardProvider);
      if (mounted) showMessage(context, '$name staat nu bij je vrienden.');
    });
  }

  void _shareCode(String code) {
    SharePlus.instance.share(ShareParams(
      text: 'Loop je mee in Kadans? Voeg me toe met mijn vriendcode $code (Uitdagingen → Samen).',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(communityStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Samen')),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e.toString().replaceFirst('Exception: ', ''),
          onRetry: () => ref.invalidate(communityStatusProvider),
        ),
        data: (s) {
          if (!s.joined) return _intro();
          if (!_refreshed && widget.refreshOnOpen) WidgetsBinding.instance.addPostFrameCallback((_) => _refreshOnce());
          return _boards(s);
        },
      ),
    );
  }

  Widget _intro() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Icon(Icons.groups_rounded, size: 56, color: challengeGold),
          const SizedBox(height: 12),
          const Text('Loop samen met anderen', textAlign: TextAlign.center, style: RwText.title),
          const SizedBox(height: 8),
          const Text(
            'Doe mee aan maandelijkse ranglijsten voor kilometers en hoogtemeters, en voeg vrienden toe met een code.',
            textAlign: TextAlign.center,
            style: TextStyle(color: RwColors.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          const RwCard(
            title: 'Wat anderen zien',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Bullet(Icons.badge_outlined, 'Alleen je bijnaam en je totaal per ranglijst.'),
              _Bullet(Icons.location_off_outlined, 'Geen locatie, routes, tijden of losse runs.'),
              _Bullet(Icons.favorite_border, 'Geen gezondheidsgegevens zoals hartslag of gewicht.'),
              _Bullet(Icons.sync_disabled, 'Runs uit Strava tellen niet mee (regels van Strava).'),
              _Bullet(Icons.logout, 'Stoppen kan altijd; dan verdwijnt alles van je uit Samen.'),
            ]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nickname,
            maxLength: 24,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _join(),
            decoration: const InputDecoration(labelText: 'Bijnaam', hintText: 'Bijv. Sem uit Utrecht', helperText: 'Gebruik liever niet je volledige naam.'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _join,
            child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Doe mee'),
          ),
        ],
      );

  Widget _boards(CommunityStatus s) {
    if (s.boards.isEmpty) return const Center(child: Text('Er loopt nu geen ranglijst.'));
    final board = s.boards.firstWhere((b) => b.key == _board, orElse: () => s.boards.first);
    final result = ref.watch(communityBoardProvider((board.key, _friends)));
    return RefreshIndicator(
      onRefresh: () async {
        _refreshed = false;
        await _refreshOnce();
        ref.invalidate(communityBoardProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in s.boards)
              ChoiceChip(
                label: Text(b.title),
                selected: b.key == board.key,
                onSelected: (_) => setState(() => _board = b.key),
              ),
          ]),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Iedereen'), icon: Icon(Icons.public)),
              ButtonSegment(value: true, label: Text('Vrienden'), icon: Icon(Icons.people_outline)),
            ],
            selected: {_friends},
            onSelectionChanged: (v) => setState(() => _friends = v.first),
          ),
          const SizedBox(height: 14),
          result.when(
            loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text(e.toString().replaceFirst('Exception: ', ''), style: const TextStyle(color: RwColors.danger)),
            data: (r) => _list(r, board),
          ),
          const SizedBox(height: 20),
          RwCard(
            title: 'Jouw vriendcode',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: SelectableText(s.friendCode ?? '—',
                      style: RwText.number.copyWith(letterSpacing: 4, color: challengeGold)),
                ),
                IconButton(
                  tooltip: 'Code delen',
                  icon: const Icon(Icons.ios_share),
                  onPressed: s.friendCode == null ? null : () => _shareCode(s.friendCode!),
                ),
              ]),
              const SizedBox(height: 4),
              Text('Je doet mee als ${s.nickname}. Deel je code, of voeg een vriend toe met zijn code.',
                  style: const TextStyle(color: RwColors.muted, fontSize: 13, height: 1.35)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _addFriend,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Vriend toevoegen'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _leave,
              child: const Text('Stoppen met Samen', style: TextStyle(color: RwColors.subtle)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BoardResult r, BoardInfo board) {
    if (r.rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          _friends ? 'Nog geen vrienden op deze ranglijst. Voeg iemand toe met zijn code.' : 'Nog niemand op deze ranglijst. Ga lopen en sta bovenaan!',
          textAlign: TextAlign.center,
          style: const TextStyle(color: RwColors.muted),
        ),
      );
    }
    final mineOutside = r.mine != null && !r.rows.any((x) => x.me);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Text('${r.total} ${r.total == 1 ? 'loper' : 'lopers'}', style: RwText.label),
          const Spacer(),
          if (r.mine != null) Text('Jij: plek ${r.mine!.rank}', style: RwText.label.copyWith(color: RwColors.accent)),
        ]),
      ),
      for (final row in r.rows) _RankRow(row: row, unit: board.unit),
      if (mineOutside) ...[
        const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Icon(Icons.more_vert, color: RwColors.subtle, size: 18)),
        _RankRow(row: r.mine!, unit: board.unit),
      ],
    ]);
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: RwColors.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: RwColors.muted, height: 1.35))),
        ]),
      );
}

const _silver = Color(0xFFC7CBD1);
const _bronze = Color(0xFFC0814B);

class _RankRow extends StatelessWidget {
  const _RankRow({required this.row, required this.unit});
  final BoardRow row;
  final String unit;

  String get _value {
    if (unit == 'km') return '${row.value.toStringAsFixed(1).replaceAll('.', ',')} km';
    if (unit == 'm') return '${row.value.round()} m';
    return '${row.value.round()} ${row.value.round() == 1 ? 'dag' : 'dagen'}';
  }

  @override
  Widget build(BuildContext context) {
    final medal = switch (row.rank) { 1 => challengeGold, 2 => _silver, 3 => _bronze, _ => null };
    return Semantics(
      label: 'Plek ${row.rank}: ${row.me ? 'jij, ' : ''}${row.nickname}, $_value',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: row.me ? RwColors.accent.withValues(alpha: 0.14) : RwColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: row.me ? RwColors.accent.withValues(alpha: 0.6) : RwColors.border),
        ),
        child: Row(children: [
          SizedBox(
            width: 34,
            child: medal != null
                ? CircleAvatar(
                    radius: 13,
                    backgroundColor: medal,
                    child: Text('${row.rank}', style: const TextStyle(color: RwColors.background, fontWeight: FontWeight.w800, fontSize: 13)),
                  )
                : Text('${row.rank}', textAlign: TextAlign.center, style: const TextStyle(color: RwColors.subtle, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(row.me ? '${row.nickname} (jij)' : row.nickname,
                    overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: row.me ? FontWeight.w800 : FontWeight.w600)),
              ),
              if (row.friend) ...[
                const SizedBox(width: 6),
                const Icon(Icons.people_outline, size: 15, color: RwColors.subtle),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Text(_value, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

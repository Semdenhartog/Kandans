import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/location_service.dart';
import '../../data/services/together_service.dart';
import '../../domain/gpx_parser.dart';
import '../../domain/geo.dart';
import '../../shared/widgets.dart';
import '../routes/route_map.dart';
import 'runner_avatar.dart';
import 'runner_profile_screen.dart';
import 'steps_contest_screen.dart' show openStepsContest;

void openBuddies(BuildContext c) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const BuddiesScreen()));
void openBets(BuildContext c) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const BetsScreen()));
void openGroups(BuildContext c) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const GroupsScreen()));

String _timesLabel(List<String> t) => t.map((x) => tr(x)).join(', ');

/// Rij met de drie Samen-extra's (bovenaan Runs in Samen).
class TogetherChips extends StatelessWidget {
  const TogetherChips({super.key});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 6, children: [
        ActionChip(avatar: const Icon(Icons.people_alt_outlined, size: 18), label: Text(tr('Loopmaatjes')), onPressed: () => openBuddies(context)),
        ActionChip(avatar: const Icon(Icons.handshake_outlined, size: 18), label: Text(tr('Weddenschappen')), onPressed: () => openBets(context)),
        ActionChip(avatar: const Icon(Icons.groups_outlined, size: 18), label: Text(tr('Loopgroepen')), onPressed: () => openGroups(context)),
        ActionChip(avatar: const Icon(Icons.directions_walk, size: 18), label: Text(tr('Stappen van de maand')), onPressed: () => openStepsContest(context)),
      ]);
}

// ---------------------------------------------------------------------------
// Loopmaatjes
// ---------------------------------------------------------------------------

class BuddiesScreen extends ConsumerStatefulWidget {
  const BuddiesScreen({super.key});

  @override
  ConsumerState<BuddiesScreen> createState() => _BuddiesScreenState();
}

class _BuddiesScreenState extends ConsumerState<BuddiesScreen> {
  final _svc = TogetherService();
  bool _loading = true, _on = false, _busy = false;
  final _note = TextEditingController();
  List<Buddy> _list = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await _svc.buddyMine();
      _on = me.on;
      _note.text = me.note ?? '';
      _list = me.on ? await _svc.buddies() : const [];
      _error = null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      if (on) {
        final loc = await ref.read(weatherLocationProvider.future);
        final runs = ref.read(activitiesProvider).value ?? const <Activity>[];
        final st = buddyStats(runs);
        await _svc.buddySet(on: true, lat: loc.latitude, lon: loc.longitude, pace: st.pace, times: st.times, note: _note.text);
      } else {
        await _svc.buddySet(on: false);
      }
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Loopmaatjes'))),
        body: _loading
            ? const LoadingView(cards: 2)
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
                      RwCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(tr('Vindbaar als loopmaatje')),
                            subtitle: Text(tr('Andere lopers in Samen zien je bijnaam, je gewone tempo, wanneer je meestal loopt en hoe ver weg je ongeveer woont (in hele km, afgerond op zo\'n 5 km). Nooit je adres of routes.')),
                            value: _on,
                            onChanged: _busy ? null : _toggle,
                          ),
                          TextField(
                            controller: _note,
                            maxLength: 80,
                            decoration: InputDecoration(labelText: tr('Korte zin (mag leeg)'), hintText: tr('Bijvoorbeeld: zoek iemand voor de lange duurloop op zondag')),
                            onSubmitted: (_) => _on ? _toggle(true) : null,
                          ),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      if (!_on)
                        Text(tr('Zet dit aan om lopers in de buurt met hetzelfde tempo te zien.'), style: TextStyle(color: RwColors.muted))
                      else if (_list.isEmpty)
                        EmptyState(
                          icon: Icons.people_alt_outlined,
                          title: tr('Nog niemand in de buurt'),
                          message: tr('Er staan nog geen lopers met een vergelijkbaar tempo binnen zo\'n 20 km. Nodig een vriend uit, of kijk later nog eens.'),
                        )
                      else
                        for (final b in _list)
                          Card(
                            child: ListTile(
                              leading: RunnerAvatar(b.nickname, size: 44),
                              title: Text(b.nickname, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text([
                                trf('± {km} km', {'km': b.km}),
                                Fmt.pace(b.paceSec.toDouble()),
                                if (b.times.isNotEmpty) _timesLabel(b.times),
                                if ((b.note ?? '').isNotEmpty) '"${b.note}"',
                              ].join(' · ')),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => openRunnerProfile(context, b.nickname),
                            ),
                          ),
                    ]),
                  ),
      );
}

// ---------------------------------------------------------------------------
// Weddenschappen
// ---------------------------------------------------------------------------

class BetsScreen extends StatefulWidget {
  const BetsScreen({super.key});

  @override
  State<BetsScreen> createState() => _BetsScreenState();
}

class _BetsScreenState extends State<BetsScreen> {
  final _svc = TogetherService();
  List<Bet> _bets = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _bets = await _svc.bets();
      _error = null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _new() async {
    final nick = TextEditingController(), stake = TextEditingController(text: tr('Een kop koffie'));
    var days = 30;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Nieuwe weddenschap'), style: RwText.title),
            const SizedBox(height: 6),
            Text(tr('Wie loopt de meeste kilometers? Alleen runs die je met Kadans opneemt of zelf toevoegt tellen mee.'),
                style: TextStyle(color: RwColors.muted)),
            const SizedBox(height: 12),
            TextField(controller: nick, decoration: InputDecoration(labelText: tr('Bijnaam van je tegenstander'))),
            const SizedBox(height: 8),
            TextField(controller: stake, maxLength: 60, decoration: InputDecoration(labelText: tr('Inzet'))),
            Wrap(spacing: 8, children: [
              for (final d in const [7, 14, 30])
                ChoiceChip(label: Text(trf('{n} dagen', {'n': d})), selected: days == d, onSelected: (_) => set(() => days = d)),
            ]),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Uitdagen'))),
          ]),
        ),
      ),
    );
    if (ok != true || nick.text.trim().isEmpty) return;
    try {
      await _svc.betCreate(nick.text.trim(), stake.text.trim().isEmpty ? tr('Een kop koffie') : stake.text.trim(), days);
      if (mounted) showMessage(context, trf('Uitdaging verstuurd naar {naam}.', {'naam': nick.text.trim()}));
      _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _answer(Bet b, bool yes) async {
    try {
      await _svc.betAnswer(b.id, yes);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Weddenschappen'))),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'bet-new',
          onPressed: _new,
          icon: const Icon(Icons.add),
          label: Text(tr('Uitdagen')),
        ),
        body: _loading
            ? const LoadingView(cards: 2)
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : _bets.isEmpty
                    ? EmptyState(
                        icon: Icons.handshake_outlined,
                        title: tr('Nog geen weddenschappen'),
                        message: tr('Daag iemand die je volgt uit: wie loopt deze maand meer? Met een kop koffie als inzet.'),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
                          for (final b in _bets) ...[_BetCard(bet: b, onAnswer: (y) => _answer(b, y)), const SizedBox(height: 10)],
                        ]),
                      ),
      );
}

class _BetCard extends StatelessWidget {
  const _BetCard({required this.bet, required this.onAnswer});
  final Bet bet;
  final void Function(bool) onAnswer;

  @override
  Widget build(BuildContext context) {
    final b = bet;
    final total = (b.myKm + b.theirKm).clamp(0.1, double.infinity);
    final leading = b.myKm >= b.theirKm;
    final status = b.open
        ? (b.iCreated ? trf('Wacht op {naam}', {'naam': b.other}) : trf('{naam} daagt je uit', {'naam': b.other}))
        : b.finished
            ? (b.myKm == b.theirKm ? tr('Gelijkspel!') : leading ? tr('Gewonnen!') : trf('{naam} won', {'naam': b.other}))
            : trf('Nog {n} dagen', {'n': b.endsOn.difference(DateTime.now()).inDays + 1});
    return RwCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          RunnerAvatar(b.other, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trf('Jij tegen {naam}', {'naam': b.other}), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(trf('Inzet: {inzet}', {'inzet': b.stake}), style: TextStyle(color: RwColors.muted, fontSize: 13)),
            ]),
          ),
          Text(status, style: TextStyle(color: b.finished && leading ? RwColors.good : RwColors.subtle, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        if (!b.open) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Row(children: [
                Expanded(flex: (b.myKm / total * 1000).round().clamp(1, 1000), child: Container(color: RwColors.accent)),
                Expanded(flex: (b.theirKm / total * 1000).round().clamp(1, 1000), child: Container(color: RwColors.bar)),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text(trf('Jij {km}', {'km': Fmt.km(b.myKm * 1000, decimals: 1)}), style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${b.other} ${Fmt.km(b.theirKm * 1000, decimals: 1)}', style: TextStyle(color: RwColors.muted)),
          ]),
        ],
        if (b.open && !b.iCreated) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => onAnswer(false), child: Text(tr('Nee, dank je')))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: () => onAnswer(true), child: Text(tr('Doe ik mee')))),
          ]),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Loopgroepen
// ---------------------------------------------------------------------------

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _svc = TogetherService();
  List<RunGroup> _groups = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _groups = await _svc.groups();
      _error = null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<String?> _ask(String title, String label, {int max = 40, bool caps = false}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: max,
          textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('Oké'))),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final name = await _ask(tr('Nieuwe loopgroep'), tr('Naam van de groep'));
    if (name == null || name.length < 2) return;
    try {
      final code = await _svc.groupCreate(name);
      if (mounted) showMessage(context, trf('Groep gemaakt. Deel de code {code} met je loopmaatjes.', {'code': code}));
      _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _join() async {
    final code = await _ask(tr('Meedoen met een groep'), tr('Code (6 tekens)'), max: 6, caps: true);
    if (code == null || code.isEmpty) return;
    try {
      final name = await _svc.groupJoin(code);
      if (mounted) showMessage(context, trf('Welkom bij {groep}!', {'groep': name}));
      _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Loopgroepen'))),
        body: _loading
            ? const LoadingView(cards: 2)
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : RefreshIndicator(onRefresh: _load, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
                    Text(tr('Een eigen groep met je loopclub, collega\'s of vrienden: een ranglijst per week en maand, en een route van de week.'),
                        style: TextStyle(color: RwColors.muted, height: 1.45)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: Text(tr('Groep maken')))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(onPressed: _join, icon: const Icon(Icons.vpn_key_outlined), label: Text(tr('Code invullen')))),
                    ]),
                    const SizedBox(height: 16),
                    for (final g in _groups)
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: RwColors.accent.withValues(alpha: 0.18), child: Icon(Icons.groups_outlined, color: RwColors.accent)),
                          title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(trf('{n} lopers · code {code}', {'n': g.members, 'code': g.code})),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GroupScreen(group: g)));
                            _load();
                          },
                        ),
                      ),
                  ])),
      );
}

class GroupScreen extends ConsumerStatefulWidget {
  const GroupScreen({super.key, required this.group});
  final RunGroup group;

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen> {
  final _svc = TogetherService();
  List<GroupRow> _rows = const [];
  List<GroupRun> _runs = const [];
  bool _month = false, _loading = true;
  late RunGroup _g = widget.group;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _rows = await _svc.board(_g.id);
      _g = (await _svc.groups()).where((x) => x.id == _g.id).firstOrNull ?? _g;
    } catch (_) {}
    try {
      _runs = await _svc.groupRuns(_g.id);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _answer(GroupRun r, bool going) async {
    try {
      await _svc.answerGroupRun(r.id, r.myAnswer == going ? null : going);
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _deleteRun(GroupRun r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Groepsrun schrappen?')),
        content: Text(tr('Iedereen in de groep ziet hem dan niet meer.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Schrappen'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.deleteGroupRun(r.id);
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _plan() async {
    final res = await showModalBottomSheet<({DateTime at, String place, double? km, String note})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _PlanGroupRunSheet(),
    );
    if (res == null) return;
    try {
      await _svc.planGroupRun(_g.id, res.at, place: res.place, km: res.km, note: res.note);
      await _load();
      if (mounted) showMessage(context, tr('Gepland. De groep ziet het in de agenda.'));
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Widget _agenda() => RwCard(
        title: tr('AGENDA'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_runs.isEmpty)
            Text(tr('Nog niets gepland. Prik een moment, dan ziet iedereen wie er komt.'), style: TextStyle(color: RwColors.muted, height: 1.4)),
          for (final r in _runs) _GroupRunTile(run: r, onAnswer: (g) => _answer(r, g), onDelete: r.canDelete ? () => _deleteRun(r) : null),
          const SizedBox(height: 4),
          TextButton.icon(onPressed: _plan, icon: const Icon(Icons.event_outlined), label: Text(tr('Groepsrun plannen'))),
        ]),
      );

  Future<void> _pickRoute() async {
    final List<RunRoute> routes = ref.read(routesProvider).value ?? await ref.read(routesProvider.future) ?? const [];
    if (!mounted) return;
    final r = await showModalBottomSheet<RunRoute>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final r in routes)
            ListTile(title: Text(r.name), subtitle: Text(Fmt.km(r.distanceMeters, decimals: 1)), onTap: () => Navigator.pop(ctx, r)),
        ]),
      ),
    );
    if (r == null) return;
    await _svc.groupSetRoute(_g.id, r.name, r.polyline);
    _load();
  }

  Future<void> _saveRoute() async {
    final p = _g.routePolyline;
    if (p == null) return;
    try {
      final route = buildRoute(decodePolyline(p), name: _g.routeName ?? tr('Route van de week'), source: 'drawn');
      await ref.read(repositoryProvider).addRoute(route);
      ref.invalidate(routesProvider);
      if (mounted) showMessage(context, tr('Route opgeslagen bij je routes.'));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = [..._rows]..sort((a, b) => (_month ? b.monthKm.compareTo(a.monthKm) : b.weekKm.compareTo(a.weekKm)));
    return Scaffold(
      appBar: AppBar(title: Text(_g.name), actions: [
        IconButton(
          tooltip: tr('Code delen'),
          icon: const Icon(Icons.share_outlined),
          onPressed: () => SharePlus.instance.share(ShareParams(
              text: trf('Loop je mee in onze Kadans-loopgroep "{groep}"? Ga in Kadans naar Samen → Loopgroepen → Code invullen: {code}', {'groep': _g.name, 'code': _g.code}))),
        ),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'leave') {
              await _svc.groupLeave(_g.id);
              if (context.mounted) Navigator.pop(context);
            }
            if (v == 'copy') Clipboard.setData(ClipboardData(text: _g.code)).ignore();
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'copy', child: Text(trf('Code kopiëren ({code})', {'code': _g.code}))),
            PopupMenuItem(value: 'leave', child: Text(tr('Groep verlaten'))),
          ],
        ),
      ]),
      body: _loading
          ? const LoadingView(cards: 2)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
                _agenda(),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: [ButtonSegment(value: false, label: Text(tr('Deze week'))), ButtonSegment(value: true, label: Text(tr('Deze maand')))],
                  selected: {_month},
                  onSelectionChanged: (v) => setState(() => _month = v.first),
                ),
                const SizedBox(height: 12),
                RwCard(
                  child: Column(children: [
                    for (final (i, r) in rows.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          SizedBox(
                            width: 28,
                            child: Text('${i + 1}',
                                style: TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, color: i == 0 ? RwColors.accent : RwColors.subtle)),
                          ),
                          RunnerAvatar(r.nickname, size: 34),
                          const SizedBox(width: 10),
                          Expanded(child: Text(r.isMe ? '${r.nickname} (${tr('jij')})' : r.nickname, style: TextStyle(fontWeight: r.isMe ? FontWeight.w800 : FontWeight.w600))),
                          Text(Fmt.km((_month ? r.monthKm : r.weekKm) * 1000, decimals: 1), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: rwTnum)),
                        ]),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                RwCard(
                  title: tr('ROUTE VAN DE WEEK'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (_g.routePolyline != null) ...[
                      SizedBox(height: 170, child: RouteMap(polyline: _g.routePolyline!, compact: true, interactive: false, showLayerToggle: false)),
                      const SizedBox(height: 8),
                      Text(_g.routeName ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(onPressed: _saveRoute, icon: const Icon(Icons.bookmark_add_outlined), label: Text(tr('Bewaar bij mijn routes'))),
                    ] else
                      Text(_g.isOwner ? tr('Kies een route die de groep deze week loopt.') : tr('De beheerder heeft nog geen route gekozen.'),
                          style: TextStyle(color: RwColors.muted)),
                    if (_g.isOwner)
                      TextButton.icon(onPressed: _pickRoute, icon: const Icon(Icons.route_outlined), label: Text(tr('Route kiezen'))),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(tr('Alleen runs die je met Kadans opneemt of zelf toevoegt tellen mee (geen Strava).'),
                    style: TextStyle(color: RwColors.subtle, fontSize: 12)),
              ]),
            ),
    );
  }
}

/// Eén groepsrun in de agenda: wanneer, waar, wie komt, en "Ik kom" / "Kan niet".
class _GroupRunTile extends StatelessWidget {
  const _GroupRunTile({required this.run, required this.onAnswer, this.onDelete});
  final GroupRun run;
  final ValueChanged<bool> onAnswer;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final r = run;
    final when = DateFormat('EEE d MMM · HH:mm', LanguageController.instance.lang.intlLocale).format(r.startsAt);
    final facts = [
      if (r.place != null) r.place!,
      if (r.distanceKm != null) Fmt.km(r.distanceKm! * 1000, decimals: r.distanceKm! % 1 == 0 ? 0 : 1),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.event_outlined, size: 18, color: RwColors.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(when, style: const TextStyle(fontWeight: FontWeight.w800))),
          if (onDelete != null)
            IconButton(
              tooltip: tr('Schrappen'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: RwColors.subtle),
              onPressed: onDelete,
            ),
        ]),
        if (facts.isNotEmpty) Text(facts, style: TextStyle(color: RwColors.muted)),
        if (r.note != null) Text(r.note!, style: TextStyle(color: RwColors.muted, height: 1.4)),
        const SizedBox(height: 4),
        Text(
          r.going == 0
              ? tr('Nog niemand aangemeld.')
              : trf('{n} komen: {namen}', {'n': r.going, 'namen': r.goingNames.join(', ')}) +
                  (r.notGoing > 0 ? ' · ${trf('{n} kunnen niet', {'n': r.notGoing})}' : ''),
          style: TextStyle(color: RwColors.subtle, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: r.myAnswer == true
                ? FilledButton.icon(onPressed: () => onAnswer(true), icon: const Icon(Icons.check, size: 18), label: Text(tr('Ik kom')))
                : OutlinedButton(onPressed: () => onAnswer(true), child: Text(tr('Ik kom'))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: r.myAnswer == false
                ? FilledButton.tonal(onPressed: () => onAnswer(false), child: Text(tr('Kan niet')))
                : OutlinedButton(onPressed: () => onAnswer(false), child: Text(tr('Kan niet'))),
          ),
        ]),
      ]),
    );
  }
}

/// Formulier om een groepsrun te plannen.
class _PlanGroupRunSheet extends StatefulWidget {
  const _PlanGroupRunSheet();

  @override
  State<_PlanGroupRunSheet> createState() => _PlanGroupRunSheetState();
}

class _PlanGroupRunSheetState extends State<_PlanGroupRunSheet> {
  late DateTime _at = () {
    final n = DateTime.now().add(const Duration(days: 1));
    return DateTime(n.year, n.month, n.day, 19);
  }();
  final _place = TextEditingController();
  final _note = TextEditingController();
  double? _km = 8;

  @override
  void dispose() {
    _place.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 89)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (!mounted) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t?.hour ?? _at.hour, t?.minute ?? _at.minute));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Groepsrun plannen'), style: TextStyle(fontFamily: RwFonts.display, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.schedule),
            label: Text(DateFormat('EEEE d MMMM · HH:mm', LanguageController.instance.lang.intlLocale).format(_at)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _place,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Verzamelplek'), hintText: tr('bijv. ingang van het park')),
          ),
          Text(tr('Afstand'), style: TextStyle(color: RwColors.muted)),
          Wrap(spacing: 8, children: [
            for (final k in [5.0, 8.0, 10.0, 15.0, 21.1])
              ChoiceChip(
                label: Text(Fmt.km(k * 1000, decimals: k % 1 == 0 ? 0 : 1)),
                selected: _km == k,
                onSelected: (on) => setState(() => _km = on ? k : null),
              ),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: _note,
            maxLength: 140,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Notitie (optioneel)'), hintText: tr('bijv. rustig tempo, koffie na afloop')),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context, (at: _at, place: _place.text.trim(), km: _km, note: _note.text.trim())),
            child: Text(tr('Plannen')),
          ),
        ]),
      );
}

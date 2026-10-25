import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/first_tips.dart';
import '../../shared/widgets.dart';

const _suggestions = [
  'Wat zal ik deze week lopen?',
  'Hoe pak ik mijn volgende wedstrijd aan?',
  'Hoe word ik sneller op de 5 km?',
  'Wat trek ik aan bij het weer van morgen?',
];

const _followUps = [
  'Wat loop ik vandaag?',
  'Hoe ging mijn week?',
  'Is mijn schema nog goed?',
  'Wat trek ik aan?',
];

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// Berichten van deze sessie die nog niet opnieuw zijn ingeladen.
  final _pending = <CoachMessage>[];
  bool _sending = false;
  int? _freeLeft;

  /// Antwoorden die al woord voor woord zijn verschenen (niet nog eens animeren).
  final _typed = <CoachMessage>{};

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _pending.add(CoachMessage(role: 'user', content: text, createdAt: DateTime.now()));
      _input.clear();
    });
    _scrollDown();
    try {
      final r = await ref.read(repositoryProvider).askCoach(text);
      setState(() {
        _pending.add(CoachMessage(role: 'assistant', content: r.reply, createdAt: DateTime.now()));
        _freeLeft = r.freeLeft;
      });
      _scrollDown();
    } on PaywallRequired {
      setState(() => _pending.removeLast());
      _input.text = text;
      if (mounted) context.push('/premium');
    } catch (e) {
      setState(() => _pending.removeLast());
      _input.text = text;
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _clear() async {
    final ok = await confirmDialog(
      context,
      title: 'Gesprek wissen?',
      message: 'Alle berichten met de coach worden verwijderd. De coach weet daarna niet meer wat jullie bespraken.',
      confirmLabel: 'Wissen',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).clearCoachChat();
      setState(_pending.clear);
      ref.invalidate(coachMessagesProvider);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(coachMessagesProvider);
    final smart = _smartQuestions(ref);
    final profile = ref.watch(profileProvider).value;
    final premium = profile?.isPremium ?? false;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Coach'),
        actions: [
          if (!premium)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _GoldPill(onTap: () => context.push('/premium')),
            ),
          IconButton(
            tooltip: 'Gesprek wissen',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          const FirstTip(
            id: 'coach',
            icon: Icons.auto_awesome,
            text: 'Stel je coach een vraag in gewone taal, zoals "Hoe train ik voor 10 km in 50 minuten?". De coach kent je runs en het weer.',
          ),
          Expanded(
            child: history.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(coachMessagesProvider),
              ),
              data: (saved) {
                final all = [...saved, ..._pending];
                if (all.isEmpty) return _Intro(onPick: _send, premium: premium, profile: profile);
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: all.length + (_sending ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == all.length) return const _Typing();
                    final m = all[i];
                    final fresh = !m.isUser && _pending.contains(m) && !_typed.contains(m);
                    return _Bubble(
                      key: ObjectKey(m),
                      message: m,
                      fresh: fresh,
                      onTyped: () => _typed.add(m),
                      onGrow: _scrollDown,
                    );
                  },
                );
              },
            ),
          ),
          if (!_sending && (history.value ?? const []).length + _pending.length > 0)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: smart.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(smart[i]),
                  onPressed: () => _send(smart[i]),
                ),
              ),
            ),
          if (!premium && _freeLeft != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _freeLeft == 0
                    ? 'Dit was je laatste gratis vraag.'
                    : 'Nog $_freeLeft gratis vra${_freeLeft == 1 ? 'ag' : 'gen'}',
                style: TextStyle(color: RwColors.subtle, fontSize: 12),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 1500,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Vraag het je coach…',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Versturen',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onPick, required this.premium, required this.profile});
  final void Function(String) onPick;
  final bool premium;
  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      children: [
        const Center(child: _CoachMark(size: 64)),
        const SizedBox(height: 16),
        const Text('Je persoonlijke hardloopcoach',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, fontFamily: RwFonts.display, fontFeatures: rwTnum)),
        const SizedBox(height: 8),
        Text(
          'De coach kijkt mee naar je runs, je wedstrijden en het weer. '
          '${premium ? '' : 'Probeer het met een paar gratis vragen.'}',
          textAlign: TextAlign.center,
          style: TextStyle(color: RwColors.muted, height: 1.5),
        ),
        const SizedBox(height: 20),
        // Suggesties als kaartjes met een eigen icoon, die één voor één binnenschuiven.
        for (final (i, s) in _suggestions.indexed)
          StaggerIn(
            index: i + 1,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RwCard(
                onTap: () => onPick(s),
                child: Row(children: [
                  TileIcon(const [Icons.calendar_today_outlined, Icons.flag_outlined, Icons.bolt_outlined, Icons.checkroom][i % 4],
                      color: RwColors.accent),
                  const SizedBox(width: 14),
                  Expanded(child: Text(s, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3))),
                  Icon(Icons.arrow_forward, size: 18, color: RwColors.subtle),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'De coach is een AI en kan zich vergissen. Geen medisch advies: bij pijn of klachten ga je naar je huisarts of fysio.',
          textAlign: TextAlign.center,
          style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.message, this.fresh = false, this.onTyped, this.onGrow});
  final CoachMessage message;
  final bool fresh;
  final VoidCallback? onTyped;
  final VoidCallback? onGrow;

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    final maxW = MediaQuery.of(context).size.width * (user ? 0.8 : 0.74);
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      constraints: BoxConstraints(maxWidth: maxW),
      decoration: BoxDecoration(
        gradient: user
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: RwColors.isDark ? const [Color(0xFF4A3A22), Color(0xFF2E2416)] : const [Color(0xFFE9DCC5), Color(0xFFE1D1B6)],
              )
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [RwColors.surface, RwColors.surface],
              ),
        border: Border.all(color: user ? RwColors.accent.withValues(alpha: 0.35) : RwColors.hairline),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(user ? 20 : 6),
          bottomRight: Radius.circular(user ? 6 : 20),
        ),
      ),
      child: user
          ? SelectableText(message.content, style: TextStyle(color: RwColors.text, height: 1.45))
          : fresh
              ? _TypeOut(text: message.content, onDone: onTyped, onGrow: onGrow)
              : SelectionArea(child: _RichReply(message.content)),
    );
    if (user) return Align(alignment: Alignment.centerRight, child: bubble);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Padding(padding: EdgeInsets.only(bottom: 6, right: 8), child: _CoachMark(size: 28)),
        Flexible(child: bubble),
      ],
    );
  }
}

/// Het embleem van de coach: een gloeiende cirkel met sterretjes.
class _CoachMark extends StatelessWidget {
  const _CoachMark({this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [RwColors.accentLight, RwColors.accent, RwColors.accentDeep],
          ),
          boxShadow: [BoxShadow(color: RwColors.accent.withValues(alpha: 0.35), blurRadius: size * 0.5)],
        ),
        child: Icon(Icons.auto_awesome, size: size * 0.55, color: RwColors.accentDark),
      );
}

/// Laat een nieuw antwoord woord voor woord verschijnen, in een rustig leestempo.
class _TypeOut extends StatefulWidget {
  const _TypeOut({required this.text, this.onDone, this.onGrow});
  final String text;
  final VoidCallback? onDone;
  final VoidCallback? onGrow;

  @override
  State<_TypeOut> createState() => _TypeOutState();
}

class _TypeOutState extends State<_TypeOut> with SingleTickerProviderStateMixin {
  late final List<int> _ends;
  late final AnimationController _c;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _ends = [for (final m in RegExp(r'\S+\s*').allMatches(widget.text)) m.end];
    final ms = (_ends.length * 32).clamp(500, 4500);
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: ms))
      ..addListener(() {
        final n = (_c.value * _ends.length).ceil();
        if (n != _shown) {
          final grewLine = n ~/ 12 != _shown ~/ 12;
          setState(() => _shown = n);
          if (grewLine) widget.onGrow?.call();
        }
      })
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) {
          widget.onDone?.call();
          widget.onGrow?.call();
        }
      });
    if (WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations || _ends.isEmpty) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_c.isCompleted) return SelectionArea(child: _RichReply(widget.text));
    final cut = _shown == 0 ? 0 : _ends[(_shown - 1).clamp(0, _ends.length - 1)];
    // De volledige tekst onzichtbaar eronder houdt de ballon meteen op zijn eindgrootte: geen verspringen.
    return Stack(children: [
      Opacity(opacity: 0, child: _RichReply(widget.text)),
      _RichReply(widget.text.substring(0, cut)),
    ]);
  }
}

/// Gouden "Premium"-label in de balk, passend bij de Premium-pagina.
class _GoldPill extends StatelessWidget {
  const _GoldPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(colors: [Color(0xFFF6E3A1), Color(0xFFD9B45A), Color(0xFF9C7A2A)]),
              boxShadow: [BoxShadow(color: const Color(0xFFD9B45A).withValues(alpha: 0.3), blurRadius: 12)],
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.workspace_premium, size: 16, color: Color(0xFF1C1405)),
              SizedBox(width: 4),
              Text('Premium', style: TextStyle(color: Color(0xFF1C1405), fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
          ),
        ),
      );
}

class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

/// Drie stipjes die om de beurt opveren, naast het coach-embleem.
class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          const _CoachMark(size: 28),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: RwColors.surface,
              border: Border.all(color: RwColors.hairline),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(6),
              ),
            ),
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < 3; i++)
                  Builder(builder: (_) {
                    final p = ((_c.value - i * 0.15) % 1);
                    final up = p < 0.4 ? (p < 0.2 ? p / 0.2 : (0.4 - p) / 0.2) : 0.0;
                    return Transform.translate(
                      offset: Offset(0, -4 * up),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.lerp(RwColors.subtle, RwColors.accent, up),
                        ),
                      ),
                    );
                  }),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Text('Coach denkt na…', style: TextStyle(color: RwColors.subtle, fontSize: 13)),
        ]),
      );
}

/// Eenvoudige opmaak van coach-antwoorden: kopjes, opsommingen, nummering en **vet**.
class _RichReply extends StatelessWidget {
  const _RichReply(this.text);
  final String text;

  static final _bold = RegExp(r'\*\*(.+?)\*\*');

  List<InlineSpan> _inline(String line, TextStyle base) {
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in _bold.allMatches(line)) {
      if (m.start > i) spans.add(TextSpan(text: line.substring(i, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      i = m.end;
    }
    if (i < line.length) spans.add(TextSpan(text: line.substring(i)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontFamily: RwFonts.body, color: RwColors.text, height: 1.45, fontSize: 15);
    final children = <Widget>[];
    for (final raw in text.trim().split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }
      final t = line.trimLeft();
      final heading = RegExp(r'^#{1,4}\s+').firstMatch(t);
      final bullet = RegExp(r'^[-*•]\s+').firstMatch(t);
      final number = RegExp(r'^(\d+)[.)]\s+').firstMatch(t);
      if (heading != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(t.substring(heading.end).replaceAll('**', ''),
              style: base.copyWith(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: 17)),
        ));
      } else if (bullet != null || number != null) {
        final m = (bullet ?? number)!;
        final indent = line.length - t.length > 1 ? 16.0 : 0.0;
        children.add(Padding(
          padding: EdgeInsets.only(left: indent, top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Text(number != null ? '${number.group(1)}.' : '•',
                    style: base.copyWith(color: RwColors.accent, fontWeight: FontWeight.w700)),
              ),
              Expanded(child: Text.rich(TextSpan(style: base, children: _inline(t.substring(m.end), base)))),
            ],
          ),
        ));
      } else {
        children.add(Text.rich(TextSpan(style: base, children: _inline(t, base))));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }
}


/// Snelle vragen die passen bij je situatie: je laatste run, je wedstrijd, je training van vandaag.
List<String> _smartQuestions(WidgetRef ref) {
  final out = <String>[];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  // De coach kijkt niet naar Strava-runs, dus daar stellen we ook geen vraag over voor.
  final runs = (ref.watch(activitiesProvider).value ?? const <Activity>[]).where((a) => !a.viaStrava).toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  if (runs.isNotEmpty) {
    final d = runs.first.startedAt.toLocal();
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) {
      out.add('Hoe was mijn run van vandaag?');
    } else if (today.difference(day).inDays == 1) {
      out.add('Hoe was mijn run van gisteren?');
    }
  }
  final races = ref.watch(racesProvider).value ?? const <RaceEvent>[];
  final next = races.where((r) => r.daysUntil >= 0 && r.daysUntil <= 21).toList()..sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
  if (next.isNotEmpty) out.add('Hoe pak ik de ${next.first.name} aan?');
  final plan = ref.watch(planProvider).value ?? const [];
  final session = plan.where((s) => s.date == today).firstOrNull;
  if (session != null) out.add('Hoe loop ik mijn ${session.title.toLowerCase()} vandaag?');
  for (final f in _followUps) {
    if (!out.contains(f)) out.add(f);
  }
  return out.take(6).toList();
}

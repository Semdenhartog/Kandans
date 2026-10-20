import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
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
    final profile = ref.watch(profileProvider).value;
    final premium = profile?.isPremium ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coach'),
        actions: [
          if (!premium)
            TextButton(
              onPressed: () => context.push('/premium'),
              child: const Text('Premium'),
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
                    return _Bubble(message: all[i]);
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
                itemCount: _followUps.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(_followUps[i]),
                  onPressed: () => _send(_followUps[i]),
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
                style: const TextStyle(color: RwColors.subtle, fontSize: 12),
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
        const Icon(Icons.auto_awesome, color: RwColors.accent, size: 40),
        const SizedBox(height: 12),
        const Text('Je persoonlijke hardloopcoach',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, fontFamily: RwFonts.display)),
        const SizedBox(height: 8),
        Text(
          'De coach kijkt mee naar je runs, je wedstrijden en het weer. '
          '${premium ? '' : 'Probeer het met een paar gratis vragen.'}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: RwColors.muted, height: 1.5),
        ),
        const SizedBox(height: 20),
        for (final s in _suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => onPick(s),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              child: Text(s),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'De coach is een AI en kan zich vergissen. Geen medisch advies: bij pijn of klachten ga je naar je huisarts of fysio.',
          textAlign: TextAlign.center,
          style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final CoachMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: user ? RwColors.accent : RwColors.surfaceHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(user ? 18 : 4),
            bottomRight: Radius.circular(user ? 4 : 18),
          ),
        ),
        child: user
            ? SelectableText(message.content, style: const TextStyle(color: RwColors.accentDark, height: 1.45))
            : SelectionArea(child: _RichReply(message.content)),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) => const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Coach denkt na…', style: TextStyle(color: RwColors.subtle)),
            ],
          ),
        ),
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
    const base = TextStyle(fontFamily: RwFonts.body, color: RwColors.text, height: 1.45, fontSize: 15);
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
              style: base.copyWith(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 17)),
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

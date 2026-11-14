import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../shared/confetti.dart';
import '../../shared/widgets.dart';
import '../../shared/art/wolkje.dart';

/// Eén nieuw record: afstand, tijd en (als bekend) de vorige beste tijd.
typedef RecordWin = ({String label, double meters, double seconds, double? previous});

/// "Hoeveel sneller" in gewone woorden, of null zonder vorig record.
String? recordGainText(RecordWin r) {
  final prev = r.previous;
  if (prev == null || prev <= r.seconds) return null;
  final d = (prev - r.seconds).round();
  if (d < 1) return tr('Net sneller dan je vorige record.');
  return trf('{tijd} sneller dan je vorige record', {'tijd': d < 60 ? '$d s' : Fmt.duration(d)});
}

/// Feestscherm na een run met een of meer nieuwe records (punt 80), met een deelkaart.
/// Altijd donker-goud, net als de ledenkaart en posters.
Future<void> openRecordCelebration(BuildContext context, List<RecordWin> records, {required DateTime date}) =>
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, a, _) => FadeTransition(opacity: a, child: RecordCelebrationScreen(records: records, date: date)),
    ));

class RecordCelebrationScreen extends StatefulWidget {
  const RecordCelebrationScreen({super.key, required this.records, required this.date});
  final List<RecordWin> records;
  final DateTime date;

  @override
  State<RecordCelebrationScreen> createState() => _RecordCelebrationScreenState();
}

class _RecordCelebrationScreenState extends State<RecordCelebrationScreen> {
  final _card = GlobalKey();
  bool _story = false, _busy = false;

  static const _bg = Color(0xFF110D06);
  static const _gold = Color(0xFFD9B45A);
  static const _goldLight = Color(0xFFF2D892);

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
  }

  RecordWin get _main {
    // Het "grootste" record vooraan: de langste afstand.
    final list = [...widget.records]..sort((a, b) => b.meters.compareTo(a.meters));
    return list.first;
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception();
      final m = _main;
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png', name: 'kadans-record.png')],
        text: trf('Nieuw record op de {afstand}: {tijd}. Gelopen met Kadans {link}',
            {'afstand': m.label, 'tijd': Fmt.duration(m.seconds), 'link': '${AppConfig.siteUrl}/'}),
      ));
    } catch (_) {
      if (mounted) showMessage(context, tr('Delen is niet gelukt. Probeer het opnieuw.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _main;
    final others = [for (final r in widget.records) if (!identical(r, m)) r];
    final gain = recordGainText(m);
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: const ColorScheme.dark(primary: _gold, onPrimary: Color(0xFF1C1405), surface: _bg),
        scaffoldBackgroundColor: _bg,
      ),
      child: Scaffold(
        body: Stack(children: [
          SafeArea(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(tooltip: tr('Sluiten'), icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ),
              Text(widget.records.length == 1 ? tr('NIEUW RECORD') : trf('{n} NIEUWE RECORDS', {'n': widget.records.length}),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _gold, fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 13)),
              const SizedBox(height: 16),
              Center(
                child: AspectRatio(
                  aspectRatio: _story ? 9 / 16 : 4 / 5,
                  child: RepaintBoundary(
                    key: _card,
                    child: _RecordCard(main: m, others: others, gain: gain, date: widget.date, story: _story),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(tr('Bericht 4:5'))),
                    ButtonSegment(value: true, label: Text(tr('Verhaal 9:16'))),
                  ],
                  selected: {_story},
                  onSelectionChanged: (v) => setState(() => _story = v.first),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _share,
                icon: const Icon(Icons.ios_share),
                label: Text(tr('Deel je record')),
              ),
              const SizedBox(height: 4),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Verder naar je run'))),
            ]),
          ),
          if (!MediaQuery.of(context).disableAnimations) const Positioned.fill(child: IgnorePointer(child: Confetti())),
        ]),
      ),
    );
  }
}

/// De deelkaart zelf: groot de tijd, de afstand, en eventueel hoeveel sneller.
class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.main, required this.others, required this.gain, required this.date, required this.story});
  final RecordWin main;
  final List<RecordWin> others;
  final String? gain;
  final DateTime date;
  final bool story;

  @override
  Widget build(BuildContext context) {
    const gold = _RecordCelebrationScreenState._gold, light = _RecordCelebrationScreenState._goldLight;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RwRadius.l),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A200D), Color(0xFF110D06)],
        ),
        border: Border.all(color: gold.withValues(alpha: 0.55), width: 1.4),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Image.asset('assets/logo/mark.png', height: 26, errorBuilder: (_, _, _) => const SizedBox(height: 26)),
          const SizedBox(width: 10),
          const Text('KADANS', style: TextStyle(color: gold, fontFamily: RwFonts.display, fontWeight: FontWeight.w800, letterSpacing: 5)),
          const Spacer(),
          Text(Fmt.dateLong(date), style: TextStyle(color: light.withValues(alpha: 0.7), fontSize: 12)),
        ]),
        const Spacer(),
        const Wolkje(size: 72, mood: WolkjeMood.blij, opensCoach: true),
        const SizedBox(height: 8),
        Text(tr('Persoonlijk record'), style: TextStyle(color: light.withValues(alpha: 0.85), fontSize: 16, fontWeight: FontWeight.w600)),
        Text(main.label,
            style: const TextStyle(color: Colors.white, fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 34, height: 1.1)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(Fmt.duration(main.seconds),
              style: TextStyle(color: light, fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: story ? 92 : 80, height: 1.05)),
        ),
        Text(Fmt.pace(main.seconds / (main.meters / 1000)),
            style: TextStyle(color: light.withValues(alpha: 0.75), fontSize: 15, fontFeatures: rwTnum)),
        if (gain != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(RwRadius.s), color: gold.withValues(alpha: 0.16)),
            child: Text(gain!, style: const TextStyle(color: light, fontWeight: FontWeight.w700)),
          ),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final o in others.take(story ? 4 : 2))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${o.label} · ${Fmt.duration(o.seconds)}',
                  style: TextStyle(color: light.withValues(alpha: 0.8), fontWeight: FontWeight.w600, fontFeatures: rwTnum)),
            ),
        ],
        const Spacer(flex: 2),
        Text(tr('Gelopen met Kadans'), style: TextStyle(color: light.withValues(alpha: 0.6), fontSize: 12, letterSpacing: 1)),
      ]),
    );
  }
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../challenges/invite_card.dart' show appInviteLink;

void openShareApp(BuildContext context, {required String name, String? friendCode}) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ShareAppScreen(name: name, friendCode: friendCode)),
    );

enum _Design { moment, year, invite }

enum _Format { post, story }

// Vaste kleuren: deelkaarten zijn altijd donker-goud (huisstijl), los van licht/donker in de app.
const _bg = Color(0xFF16120D);
const _surface = Color(0xFF221C15);
const _gold = Color(0xFFD9BF92);
const _goldLight = Color(0xFFF0DDB6);
const _goldDeep = Color(0xFFB8955F);
const _text = Color(0xFFF4EDE2);
const _muted = Color(0xFFB7AA97);

/// Kadans aanraden met een mooie kaart in plaats van een kale link: drie ontwerpen, als bericht (4:5) of
/// verhaal (9:16, voor Instagram/WhatsApp-status), met je eigen cijfers en een eigen tekstje.
class ShareAppScreen extends ConsumerStatefulWidget {
  const ShareAppScreen({super.key, required this.name, this.friendCode});
  final String name;
  final String? friendCode;

  @override
  ConsumerState<ShareAppScreen> createState() => _ShareAppScreenState();
}

class _ShareAppScreenState extends ConsumerState<ShareAppScreen> {
  final _key = GlobalKey();
  final _note = TextEditingController();
  _Design _design = _Design.moment;
  _Format _format = _Format.post;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _link =>
      widget.friendCode == null ? appInviteLink() : '${appInviteLink()}&code=${Uri.encodeQueryComponent(widget.friendCode!)}';

  Future<void> _share() async {
    setState(() => _busy = true);
    final note = _note.text.trim();
    final text = '${note.isEmpty ? tr('Ik loop met Kadans: die zegt wanneer je het best kunt gaan.') : note} '
        '${tr('Probeer hem ook:')} $_link';
    try {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('leeg');
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png', name: 'kadans.png')],
        text: text,
        subject: tr('Probeer Kadans'),
      ));
    } catch (_) {
      await SharePlus.instance.share(ShareParams(text: text, subject: tr('Probeer Kadans')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final stats = _YearStats.of(runs);
    final size = _format == _Format.post ? const Size(360, 450) : const Size(360, 640);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Kadans delen'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<_Format>(
            segments: [
              ButtonSegment(value: _Format.post, icon: const Icon(Icons.crop_portrait), label: Text(tr('Bericht'))),
              ButtonSegment(value: _Format.story, icon: const Icon(Icons.smartphone), label: Text(tr('Verhaal'))),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 12),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: _format == _Format.post ? 420 : 520),
              child: AspectRatio(
                aspectRatio: size.width / size.height,
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _key,
                    child: SizedBox.fromSize(
                      size: size,
                      child: _Card(design: _design, story: _format == _Format.story, name: widget.name, stats: stats, code: widget.friendCode),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (final (d, label) in [
              (_Design.moment, 'Beste moment'),
              (_Design.year, 'Mijn cijfers'),
              (_Design.invite, 'Uitnodiging'),
            ])
              ChoiceChip(label: Text(tr(label)), selected: _design == d, onSelected: (_) => setState(() => _design = d)),
          ]),
          if (_design == _Design.year && stats.runs == 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('Nog geen eigen runs dit jaar; na je eerste run staan je cijfers op de kaart.'),
                  textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted, fontSize: 13)),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLength: 140,
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              labelText: tr('Je eigen tekstje (mag leeg)'),
              hintText: tr('Bijv. "Deze app zegt wanneer het droog is, ga je mee?"'),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _share,
            icon: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.ios_share),
            label: Text(tr('Delen')),
          ),
          const SizedBox(height: 8),
          Text(
            _format == _Format.story
                ? tr('Tip: kies Instagram → Verhaal. Plak de link dan als linksticker.')
                : tr('De kaart gaat mee als foto, met je tekstje en de link eronder.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: RwColors.subtle, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Eigen cijfers van dit jaar, zonder Strava-runs (die mogen niet naar anderen).
class _YearStats {
  const _YearStats(this.km, this.runs, this.hours);
  final double km;
  final int runs;
  final double hours;

  static _YearStats of(List<Activity> all) {
    final y = DateTime.now().year;
    var km = 0.0, secs = 0, n = 0;
    for (final a in all) {
      if (a.startedAt.toLocal().year != y) continue;
      if (a.source == 'strava' || (a.externalId ?? '').startsWith('viastrava-')) continue;
      km += a.distanceMeters / 1000;
      secs += a.movingTimeSeconds;
      n++;
    }
    return _YearStats(km, n, secs / 3600);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.design, required this.story, required this.name, required this.stats, this.code});
  final _Design design;
  final bool story;
  final String name;
  final _YearStats stats;
  final String? code;

  TextStyle _display(double size, {Color color = _text, FontWeight weight = FontWeight.w800}) =>
      TextStyle(fontFamily: RwFonts.display, fontSize: size, height: 1.05, color: color, fontWeight: weight, fontFeatures: rwTnum);

  TextStyle _body(double size, {Color color = _muted}) => TextStyle(fontFamily: RwFonts.body, fontSize: size, height: 1.35, color: color);

  Widget _logo(double h) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Image.asset('assets/logo/k_goud.webp', height: h, filterQuality: FilterQuality.high),
        SizedBox(width: h * 0.24),
        Padding(
          padding: EdgeInsets.only(bottom: h * 0.02),
          child: Image.asset('assets/logo/adans.png', height: h * 0.42, color: _gold, filterQuality: FilterQuality.high),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final body = switch (design) {
      _Design.moment => _moment(),
      _Design.year => _year(),
      _Design.invite => _invite(),
    };
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _bg,
        gradient: RadialGradient(center: Alignment(0, -0.45), radius: 0.9, colors: [Color(0xFF3A2F22), _bg]),
      ),
      child: Stack(children: [
        // Dunne gouden routelijn onderin, zoals op de andere Kadans-kaarten.
        Positioned.fill(child: CustomPaint(painter: _RoutePainter())),
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _goldDeep.withValues(alpha: 0.8), width: 1),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(30, story ? 70 : 36, 30, story ? 70 : 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: _logo(story ? 48 : 40)),
            const Spacer(),
            body,
            const Spacer(),
            _footer(),
          ]),
        ),
      ]),
    );
  }

  Widget _footer() => Column(children: [
        Text('BESTE MOMENT  ·  WIND OP JE ROUTE  ·  COACH',
            textAlign: TextAlign.center, style: _display(8.5, color: _muted, weight: FontWeight.w700).copyWith(letterSpacing: 1.6)),
        const SizedBox(height: 6),
        Text(tr('Gratis te proberen · Android'), textAlign: TextAlign.center, style: _body(10)),
      ]);

  Widget _moment() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Ik loop op het beste moment.'), textAlign: TextAlign.center, style: _display(story ? 34 : 30)),
        const SizedBox(height: 10),
        Text(tr('Kadans kijkt naar weer, wind op je route en buien, en zegt wanneer je het best kunt gaan.'),
            textAlign: TextAlign.center, style: _body(12.5)),
        SizedBox(height: story ? 34 : 22),
        // Voorbeeld van wat je in de app ziet.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _goldDeep.withValues(alpha: 0.6)),
          ),
          child: Row(children: [
            SizedBox(
              width: 62,
              height: 62,
              child: Stack(alignment: Alignment.center, children: [
                const SizedBox.expand(
                  child: CircularProgressIndicator(value: 0.92, strokeWidth: 5, color: _gold, backgroundColor: Color(0xFF3A2F22)),
                ),
                Text('92', style: _display(20, color: _goldLight)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('VANDAAG BESTE MOMENT'), style: _display(8.5, color: _muted, weight: FontWeight.w700).copyWith(letterSpacing: 1.2)),
                const SizedBox(height: 2),
                Text('18:40', style: _display(30, color: _goldLight)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.wb_sunny_outlined, size: 13, color: _gold),
                  const SizedBox(width: 3),
                  Text('11°', style: _body(11, color: _text)),
                  const SizedBox(width: 10),
                  const Icon(Icons.air, size: 13, color: _gold),
                  const SizedBox(width: 3),
                  Flexible(child: Text(tr('wind mee terug'), style: _body(11, color: _text))),
                ]),
              ]),
            ),
          ]),
        ),
      ]);

  Widget _year() {
    final y = DateTime.now().year;
    String n(double v) => v.round().toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(name.isEmpty ? trf('Mijn {jaar} met Kadans', {'jaar': y}) : trf('{naam} loopt met Kadans', {'naam': name}),
          textAlign: TextAlign.center, style: _display(story ? 30 : 26)),
      SizedBox(height: story ? 36 : 24),
      Text(n(stats.km), textAlign: TextAlign.center, style: _display(story ? 96 : 80, color: _goldLight)),
      Text(trf('kilometer in {jaar}', {'jaar': y}), textAlign: TextAlign.center, style: _body(13, color: _gold)),
      SizedBox(height: story ? 30 : 20),
      Row(children: [
        Expanded(child: _stat('${stats.runs}', tr('runs'))),
        Container(width: 1, height: 34, color: _goldDeep.withValues(alpha: 0.5)),
        Expanded(child: _stat(n(stats.hours), tr('uur onderweg'))),
      ]),
      SizedBox(height: story ? 30 : 20),
      Text(tr('Elke run op het beste moment van de dag.'), textAlign: TextAlign.center, style: _body(12.5)),
    ]);
  }

  Widget _stat(String v, String l) => Column(children: [
        Text(v, style: _display(26, color: _text)),
        Text(l, style: _body(11)),
      ]);

  Widget _invite() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(name.isEmpty ? tr('Een uitnodiging voor jou') : trf('{naam} nodigt je uit', {'naam': name}),
            textAlign: TextAlign.center, style: _display(story ? 32 : 28)),
        const SizedBox(height: 8),
        Text(code == null ? tr('Loop op het beste moment') : tr('om samen te lopen'), textAlign: TextAlign.center, style: _body(14)),
        SizedBox(height: story ? 40 : 26),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold, width: 1.2),
          ),
          child: Column(children: [
            Text(code == null ? tr('TIK OP DE LINK') : tr('VRIENDCODE'),
                style: _display(9, color: _muted, weight: FontWeight.w700).copyWith(letterSpacing: 2.4)),
            const SizedBox(height: 6),
            Text(code == null ? tr('Probeer Kadans') : code!.split('').join(' '), style: _display(28, color: _goldLight)),
          ]),
        ),
        if (code != null) ...[
          const SizedBox(height: 12),
          Text(tr('Open de link, dan staan we meteen bij elkaars vrienden.'), textAlign: TextAlign.center, style: _body(11.5)),
        ],
      ]);
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(-10, s.height * 0.8)
      ..cubicTo(s.width * 0.2, s.height * 0.7, s.width * 0.3, s.height * 0.9, s.width * 0.5, s.height * 0.82)
      ..cubicTo(s.width * 0.7, s.height * 0.74, s.width * 0.8, s.height * 0.86, s.width + 10, s.height * 0.76);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _gold.withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(_RoutePainter old) => false;
}

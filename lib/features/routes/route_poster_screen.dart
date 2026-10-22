import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../shared/widgets.dart';
import 'route_shape.dart';

/// Deel een route als poster: strakke lijn, naam en de cijfers. Mooi voor je story of om te printen.
void openRoutePoster(BuildContext context, RunRoute r, {int? fastestSeconds, int timesRun = 0}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => RoutePosterScreen(route: r, fastestSeconds: fastestSeconds, timesRun: timesRun),
  ));
}

enum _PosterStyle {
  nacht('Nacht', Color(0xFF0E0E12), Color(0xFFF5F5F7), Color(0xFFFF7A1A)),
  zand('Zand', Color(0xFFF1E9DC), Color(0xFF1E1B18), Color(0xFFC2410C)),
  bos('Bos', Color(0xFF12261C), Color(0xFFEAF4EC), Color(0xFFFFB547));

  const _PosterStyle(this.label, this.bg, this.fg, this.line);
  final String label;
  final Color bg, fg, line;
}

class RoutePosterScreen extends StatefulWidget {
  const RoutePosterScreen({super.key, required this.route, this.fastestSeconds, this.timesRun = 0});
  final RunRoute route;
  final int? fastestSeconds;
  final int timesRun;

  @override
  State<RoutePosterScreen> createState() => _RoutePosterScreenState();
}

class _RoutePosterScreenState extends State<RoutePosterScreen> {
  final _key = GlobalKey();
  _PosterStyle _style = _PosterStyle.nacht;
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('geen afbeelding');
      final safe = widget.route.name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim().replaceAll(' ', '-');
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png', name: 'runwise-${safe.isEmpty ? 'route' : safe}.png')],
        text: '${widget.route.name} · ${Fmt.km(widget.route.distanceMeters, decimals: 1)} · gemaakt met RunWise',
      ));
    } catch (_) {
      if (mounted) showMessage(context, 'Delen is niet gelukt. Probeer het opnieuw.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    final s = _style;
    Widget stat(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: TextStyle(color: s.fg.withValues(alpha: 0.55), fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(color: s.fg, fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 26, fontWeight: FontWeight.w800)),
        ]);

    return Scaffold(
      appBar: AppBar(title: const Text('Route als poster')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: RepaintBoundary(
                    key: _key,
                    child: Container(
                      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(4)),
                      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(r.name.toUpperCase(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: s.fg, fontFamily: RwFonts.display, fontSize: 30, fontWeight: FontWeight.w800, height: 1.05)),
                        const SizedBox(height: 6),
                        Align(alignment: Alignment.centerLeft, child: Container(height: 3, width: 48, color: s.line)),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: _TintedShape(polyline: r.polyline, color: s.line),
                          ),
                        ),
                        Row(children: [
                          Expanded(child: stat('Afstand', Fmt.km(r.distanceMeters, decimals: 1))),
                          Expanded(
                              child: stat('Hoogte', r.elevationGainMeters == null ? '–' : '${r.elevationGainMeters!.round()} m')),
                          Expanded(
                            child: widget.fastestSeconds != null
                                ? stat('Snelste', Fmt.duration(widget.fastestSeconds!))
                                : stat('Gelopen', '${widget.timesRun}×'),
                          ),
                        ]),
                        const SizedBox(height: 18),
                        Row(children: [
                          Text('RUNWISE',
                              style: TextStyle(
                                  color: s.fg.withValues(alpha: 0.7), fontFamily: RwFonts.display, fontWeight: FontWeight.w800, letterSpacing: 3)),
                          const Spacer(),
                          Text('loop op het beste moment', style: TextStyle(color: s.fg.withValues(alpha: 0.45), fontSize: 11)),
                        ]),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<_PosterStyle>(
                segments: [for (final st in _PosterStyle.values) ButtonSegment(value: st, label: Text(st.label))],
                selected: {_style},
                onSelectionChanged: (v) => setState(() => _style = v.first),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _busy ? null : _share,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.ios_share),
                label: const Text('Deel poster'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Routevorm in een eigen kleur (RouteShape gebruikt de accentkleur; die verven we over).
class _TintedShape extends StatelessWidget {
  const _TintedShape({required this.polyline, required this.color});
  final String polyline;
  final Color color;

  @override
  Widget build(BuildContext context) => ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: RouteShape(polyline: polyline, strokeWidth: 5),
      );
}

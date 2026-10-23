import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../shared/widgets.dart';
import '../luxe/luxe.dart';
import 'poster_design.dart';
import 'poster_order_screen.dart';

/// Deel een route als poster: strakke lijn, naam en de cijfers. Mooi voor je story of om te laten drukken.
void openRoutePoster(BuildContext context, RunRoute r, {int? fastestSeconds, int timesRun = 0}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => RoutePosterScreen(route: r, fastestSeconds: fastestSeconds, timesRun: timesRun),
  ));
}

class RoutePosterScreen extends ConsumerStatefulWidget {
  const RoutePosterScreen({super.key, required this.route, this.fastestSeconds, this.timesRun = 0});
  final RunRoute route;
  final int? fastestSeconds;
  final int timesRun;

  @override
  ConsumerState<RoutePosterScreen> createState() => _RoutePosterScreenState();
}

class _RoutePosterScreenState extends ConsumerState<RoutePosterScreen> {
  final _key = GlobalKey();
  PosterStyle _style = PosterStyle.nacht;
  bool _busy = false;

  PosterData get _data => PosterData(
        title: widget.route.name,
        polyline: widget.route.polyline,
        distanceMeters: widget.route.distanceMeters,
        elevationGainMeters: widget.route.elevationGainMeters,
        fastestSeconds: widget.fastestSeconds,
        timesRun: widget.timesRun,
      );

  /// Luxe stijl gekozen maar nog niet ontgrendeld? Dan eerst het verkoopvenster.
  Future<bool> _unlockedFor(PosterStyle s) async {
    if (!s.isLuxe) return true;
    if (await ref.read(luxeAccessProvider.future)) return true;
    if (!mounted) return false;
    return showLuxeSheet(context, ref);
  }

  Future<void> _share() async {
    if (!await _unlockedFor(_style)) return;
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

  Future<void> _order() async {
    if (!await _unlockedFor(_style)) return;
    if (!mounted) return;
    openPosterOrder(context, data: _data, style: _style);
  }

  @override
  Widget build(BuildContext context) {
    final owned = ref.watch(luxeAccessProvider).value ?? false;
    final locked = _style.isLuxe && !owned;
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
                  child: Stack(fit: StackFit.expand, children: [
                    RepaintBoundary(
                      key: _key,
                      child: ClipRRect(borderRadius: BorderRadius.circular(4), child: RoutePosterArt(data: _data, style: _style)),
                    ),
                    if (locked) const Positioned(right: 10, top: 10, child: LuxeBadge()),
                  ]),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 76,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: PosterStyle.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final st = PosterStyle.values[i];
                final sel = st == _style;
                return Semantics(
                  button: true,
                  selected: sel,
                  label: 'Stijl ${st.label}${st.isLuxe ? ', luxe' : ''}',
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _style = st);
                    },
                    child: Column(children: [
                      Stack(clipBehavior: Clip.none, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: st.background),
                            border: Border.all(
                              color: sel ? (st.isLuxe ? luxeGold : RwColors.accent) : RwColors.border,
                              width: sel ? 3 : 1,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 14,
                              height: 4,
                              decoration: BoxDecoration(color: st.line, borderRadius: BorderRadius.circular(2)),
                            ),
                          ),
                        ),
                        if (st.isLuxe && !owned) const Positioned(right: -4, top: -4, child: Icon(Icons.lock, size: 14, color: luxeGold)),
                      ]),
                      const SizedBox(height: 4),
                      Text(st.label,
                          style: TextStyle(
                              fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? RwColors.text : RwColors.subtle)),
                    ]),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _busy ? null : _share,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(locked ? Icons.lock_outline : Icons.ios_share),
                  label: const Text('Delen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _busy ? null : _order,
                  icon: Icon(locked ? Icons.lock_outline : Icons.local_shipping_outlined),
                  label: const Text('Laten drukken'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

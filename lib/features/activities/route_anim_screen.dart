import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/video_encoder.dart';
import '../../domain/geo.dart';
import '../../domain/route_anim.dart';
import '../../domain/route_geometry.dart';
import '../../domain/run_streams.dart';
import '../../shared/widgets.dart';
import 'route_anim_painter.dart';

void openRouteAnim(BuildContext context, Activity a, {RunRoute? route}) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RouteAnimScreen(activity: a, route: route)));
}

/// Bewegende video van je route (tekenen, komeet, kilometers, tempo, echo): voorbeeld, maken, delen.
class RouteAnimScreen extends ConsumerStatefulWidget {
  const RouteAnimScreen({super.key, required this.activity, this.route});
  final Activity activity;
  final RunRoute? route;

  @override
  ConsumerState<RouteAnimScreen> createState() => _RouteAnimScreenState();
}

class _RouteAnimScreenState extends ConsumerState<RouteAnimScreen> with SingleTickerProviderStateMixin {
  static const _w = 720, _h = 1280;

  late final AnimationController _ctl;
  RouteAnimStyle _style = RouteAnimStyle.draw;
  bool _hideHome = true;
  List<LatLng> _raw = const [];
  ui.Image? _logo;
  RouteAnimData? _data;
  double? _progress; // 0..1 tijdens het maken
  String? _videoPath;
  bool _cancel = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: Duration(milliseconds: (_style.seconds * 1000).round()))..repeat();
    final a = widget.activity;
    final line = a.hasTrack ? a.trackPolyline! : widget.route?.polyline;
    _raw = line == null ? const [] : decodePolyline(line);
    final id = a.id;
    if (id != null) {
      ref.read(activityStreamsProvider(id).future).then((_) {
        if (mounted) _rebuild();
      }).ignore();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rebuild();
    });
    _loadLogo();
  }

  Future<void> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/logo/k_goud.webp');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetHeight: 144);
      final img = (await codec.getNextFrame()).image;
      if (!mounted) return;
      setState(() => _logo = img);
      _rebuild();
    } catch (_) {}
  }

  @override
  void dispose() {
    _cancel = true;
    _ctl.dispose();
    if (_progress != null) VideoEncoder.cancel();
    super.dispose();
  }

  /// Streams (tempo per stuk) van deze run, als die er zijn.
  RunStreams? get _streams {
    final id = widget.activity.id;
    if (id == null) return null;
    return RunStreams.fromJson(ref.read(activityStreamsProvider(id)).value);
  }

  void _rebuild() {
    final a = widget.activity;
    final shown = _hideHome ? trimPrivacyZone(_raw, radius: 300) : _raw;
    final path = RoutePath.fit(shown, RouteAnimPainter.routeBox);
    if (path == null) {
      setState(() => _data = null);
      return;
    }
    var spans = <PaceSpan>[];
    double? slow, fast;
    final s = _streams;
    if (s != null && _raw.length > 2) {
      final segs = valueSegments(s);
      if (segs.length >= 4) {
        final values = [for (final x in segs) x.value]..sort();
        final lo = values[(values.length * 0.1).floor()];
        final hi = values[(values.length * 0.9).floor().clamp(0, values.length - 1)];
        slow = hi;
        fast = lo;
        final colored = [
          for (final x in segs)
            (points: x.points, color: routeAnimPaceColor(hi - lo < 1e-9 ? 0.5 : 1 - ((x.value - lo) / (hi - lo)).clamp(0.0, 1.0)))
        ];
        spans = mergePaceSpans(paceSpansFor(_raw, shown, colored));
      }
    }
    final fullLen = trackMeters(_raw);
    final shownLen = trackMeters(shown);
    final start = _hideHome && _raw.length > 1 && shown.isNotEmpty ? _lenBefore(shown.first) : 0.0;
    var title = a.title ?? '';
    if (title.isEmpty) title = Fmt.date(a.startedAt);
    setState(() => _data = RouteAnimData(
          path: path,
          label: title,
          meters: a.distanceMeters > 0 ? a.distanceMeters : fullLen,
          seconds: a.movingTimeSeconds.toDouble(),
          pathMeters: shownLen,
          trimStartMeters: start,
          spans: spans,
          slowPace: slow,
          fastPace: fast,
          logo: _logo,
        ));
    if (spans.isEmpty && _style == RouteAnimStyle.pace) _setStyle(RouteAnimStyle.draw);
  }

  double _lenBefore(LatLng p) {
    var s = 0.0;
    for (var i = 1; i < _raw.length; i++) {
      if (identical(_raw[i - 1], p)) break;
      s += distanceMeters(_raw[i - 1], _raw[i]);
    }
    return s;
  }

  void _setStyle(RouteAnimStyle s) {
    if (_progress != null) return;
    setState(() {
      _style = s;
      _videoPath = null;
      _error = null;
    });
    _ctl
      ..duration = Duration(milliseconds: (s.seconds * 1000).round())
      ..repeat();
  }

  Future<void> _make() async {
    final data = _data;
    if (data == null || _progress != null) return;
    _cancel = false;
    _ctl.stop();
    setState(() {
      _progress = 0;
      _videoPath = null;
      _error = null;
    });
    try {
      final style = _style;
      final n = style.frames;
      final enc = await VideoEncoder.begin(width: _w, height: _h, fps: routeAnimFps);
      for (var i = 0; i < n; i++) {
        if (_cancel || !mounted) {
          await VideoEncoder.cancel();
          return;
        }
        final t = i / routeAnimFps;
        final rgba = await renderRouteAnimFrame(RouteAnimPainter(style: style, data: data, t: t), _w, _h);
        await enc.frame(rgba, i);
        // Even ruimte voor het scherm (Stoppen, voortgangsbalk), ook op trage toestellen.
        await Future<void>.delayed(Duration.zero);
        if (i % 4 == 0 && mounted) setState(() => _progress = i / n);
      }
      final path = await enc.finish();
      if (!mounted) return;
      setState(() => _videoPath = path);
      HapticFeedback.mediumImpact();
    } catch (_) {
      await VideoEncoder.cancel();
      if (mounted) setState(() => _error = tr('De video maken is niet gelukt.'));
    } finally {
      if (mounted) {
        setState(() => _progress = null);
        _ctl.repeat();
      }
    }
  }

  Future<void> _share() async {
    final p = _videoPath;
    if (p == null) return;
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(p, mimeType: 'video/mp4', name: 'kadans-route.mp4')],
        text: '${Fmt.km(widget.activity.distanceMeters, decimals: 1)} gelopen met Kadans ${AppConfig.siteUrl}/',
      ));
    } catch (_) {
      if (mounted) showMessage(context, tr('Delen is niet gelukt. Probeer het opnieuw.'), error: true);
    }
  }

  Future<void> _instagram() async {
    final p = _videoPath;
    if (p == null || !File(p).existsSync()) return;
    final ok = await VideoEncoder.openInInstagram(p);
    if (!ok && mounted) showMessage(context, tr('Instagram is niet te openen. Kies "Deel video" en dan Instagram.'), error: true);
  }

  String _name(RouteAnimStyle s) => switch (s) {
        RouteAnimStyle.draw => tr('Tekenen'),
        RouteAnimStyle.comet => tr('Komeet'),
        RouteAnimStyle.km => tr('Kilometers'),
        RouteAnimStyle.pace => tr('Tempo'),
        RouteAnimStyle.echo => tr('Echo'),
      };

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final busy = _progress != null;
    final styles = [
      for (final s in RouteAnimStyle.values)
        if (s != RouteAnimStyle.pace || (data?.spans.isNotEmpty ?? false)) s
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Bewegende video van je route'))),
      body: SafeArea(
        child: _raw.length < 2
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('Van deze run is geen route bewaard.'), textAlign: TextAlign.center)))
            : Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: AspectRatio(
                          aspectRatio: 9 / 16,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(RwRadius.m),
                            child: data == null
                                ? const ColoredBox(color: Color(0xFF1A1410))
                                : AnimatedBuilder(
                                    animation: _ctl,
                                    builder: (_, __) => CustomPaint(
                                      painter: RouteAnimPainter(style: _style, data: data, t: _ctl.value * _style.seconds),
                                      size: Size.infinite,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<RouteAnimStyle>(
                          showSelectedIcon: false,
                          segments: [for (final s in styles) ButtonSegment(value: s, label: Text(_name(s)))],
                          selected: {_style},
                          onSelectionChanged: busy ? null : (v) => _setStyle(v.first),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _hideHome,
                          onChanged: busy
                              ? null
                              : (v) {
                                  _hideHome = v;
                                  _videoPath = null;
                                  _rebuild();
                                },
                          title: Text(tr('Verberg waar je woont')),
                          subtitle: Text(tr('Laat de eerste en laatste 300 m van je route weg')),
                        ),
                        if (_error != null)
                          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: RwColors.danger))),
                        if (busy) ...[
                          LinearProgressIndicator(value: _progress),
                          const SizedBox(height: 8),
                          TextButton(onPressed: () => _cancel = true, child: Text(tr('Stoppen'))),
                        ] else if (_videoPath == null)
                          FilledButton.icon(onPressed: data == null ? null : _make, icon: const Icon(Icons.movie_creation_outlined), label: Text(tr('Maak video')))
                        else ...[
                          FilledButton.icon(onPressed: _share, icon: const Icon(Icons.ios_share), label: Text(tr('Deel video'))),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(child: OutlinedButton(onPressed: _instagram, child: Text(tr('Naar Instagram')))),
                            const SizedBox(width: 8),
                            Expanded(child: OutlinedButton(onPressed: _make, child: Text(tr('Opnieuw maken')))),
                          ]),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

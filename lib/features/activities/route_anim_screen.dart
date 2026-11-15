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
import 'route_anim_controls.dart';
import 'route_anim_editor.dart';
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
  final _ed = RouteAnimEditor();
  String? _shownTitle;

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
    _ed.load().then((_) {
      if (mounted && !_ed.layout.isDefault) _rebuild();
    });
    _ed.addListener(_onEdit);
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

  Future<void> _editTitle() async {
    final c = TextEditingController(text: _data?.label ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Titel boven de video')),
        content: TextField(controller: c, autofocus: true, maxLength: 26, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuleren'))),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('Opslaan'))),
        ],
      ),
    );
    if (v != null) _ed.setTitle(v);
  }

  /// De editor (foto, plek van de tekst, titel) is veranderd: een eerder gemaakte video klopt niet meer.
  void _onEdit() {
    if (!mounted) return;
    _videoPath = null;
    final d = _data;
    // Alleen verplaatsen of zoomen: goedkoop bijwerken. Andere foto of titel: alles opnieuw opbouwen.
    if (d != null && identical(d.background, _ed.bg) && _ed.title == _shownTitle) {
      setState(() => _data = d.copyWith(layout: _ed.layout, photoZoom: _ed.zoom, photoPan: _ed.pan));
    } else {
      _rebuild();
    }
  }

  @override
  void dispose() {
    _cancel = true;
    _ctl.dispose();
    _ed.removeListener(_onEdit);
    _ed.dispose();
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
    _shownTitle = _ed.title;
    var title = _ed.title ?? a.title ?? '';
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
          background: _ed.bg,
          layout: _ed.layout,
          photoZoom: _ed.zoom,
          photoPan: _ed.pan,
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
    } catch (e) {
      await VideoEncoder.cancel();
      if (mounted) setState(() => _error = _reason(e));
    } finally {
      if (mounted) {
        setState(() => _progress = null);
        _ctl.repeat();
      }
    }
  }

  /// Korte, begrijpelijke reden uit de fout van de encoder (de telefoon geeft meestal een Engelse tekst mee).
  String _reason(Object e) {
    final m = (e is PlatformException ? e.message : null) ?? '';
    if (m.contains('ondersteunt')) return tr('Dit toestel ondersteunt dit videoformaat niet.');
    if (m.contains('reageert niet')) return tr('De videoencoder reageert niet. Sluit andere apps en probeer het opnieuw.');
    return tr('De video maken is niet gelukt.');
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
                                : LayoutBuilder(builder: (_, box) {
                                    final k = routeAnimDesign.width / box.maxWidth;
                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onScaleStart: busy ? null : (d) => setState(() => _ed.start(_style, d.localFocalPoint * k)),
                                      onScaleUpdate: busy ? null : (d) => _ed.update(_style, d.focalPointDelta * k, d.scale),
                                      onScaleEnd: busy ? null : (_) => setState(_ed.end),
                                      // Eén painter die zelf meeloopt met de klok: geen nieuwe widgetboom per beeld.
                                      child: RepaintBoundary(
                                        child: CustomPaint(
                                          painter: RouteAnimPainter(
                                            style: _style,
                                            data: data,
                                            clock: () => _ctl.value * _style.seconds,
                                            repaint: _ctl,
                                            highlight: _ed.drag,
                                          ),
                                          size: Size.infinite,
                                        ),
                                      ),
                                    );
                                  }),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(tr('Sleep de tekst of het logo om ze te verplaatsen'), style: TextStyle(fontSize: 12, color: RwColors.muted)),
                  RouteAnimControls(
                    styles: styles,
                    style: _style,
                    styleName: _name,
                    busy: busy,
                    progress: _progress,
                    hasData: data != null,
                    hasPhoto: _ed.bg != null,
                    layoutChanged: !_ed.layout.isDefault,
                    hideHome: _hideHome,
                    hasVideo: _videoPath != null,
                    error: _error,
                    onStyle: _setStyle,
                    onPhoto: () => _ed.pickPhoto().then((ok) {
                      if (!ok && mounted) showMessage(context, tr('De foto kon niet worden geladen.'), error: true);
                    }),
                    onTitle: _editTitle,
                    onClearPhoto: _ed.clearPhoto,
                    onResetLayout: _ed.resetLayout,
                    onHideHome: (v) {
                      _hideHome = v;
                      _videoPath = null;
                      _rebuild();
                    },
                    onMake: _make,
                    onStop: () => _cancel = true,
                    onShare: _share,
                    onInstagram: _instagram,
                  ),
                ],
              ),
      ),
    );
  }
}

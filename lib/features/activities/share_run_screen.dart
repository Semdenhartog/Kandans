import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../domain/geo.dart';
import '../../domain/route_geometry.dart';
import '../../domain/weather_correction.dart';
import '../../shared/widgets.dart';
import '../routes/route_map.dart' show windColor;

void openShareRun(BuildContext context, Activity a, {RunRoute? route, List<String> badges = const []}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ShareRunScreen(activity: a, route: route, badges: badges),
  ));
}

enum _CardStyle { donker, oranje, foto }

/// Maakt een mooie afbeelding van je run om te delen (Instagram, WhatsApp, ...).
class ShareRunScreen extends StatefulWidget {
  const ShareRunScreen({super.key, required this.activity, this.route, this.badges = const []});
  final Activity activity;
  final RunRoute? route;
  final List<String> badges;

  @override
  State<ShareRunScreen> createState() => _ShareRunScreenState();
}

class _ShareRunScreenState extends State<ShareRunScreen> {
  final _key = GlobalKey();
  _CardStyle _style = _CardStyle.donker;
  bool _busy = false;

  /// Privacyzone: begin en eind van de route niet tonen (standaard aan).
  bool _hideHome = true;
  static const _prefKey = 'share_hide_home';

  /// Eerste foto bij de run, als achtergrond voor de deelkaart.
  Uint8List? _photo;

  @override
  void initState() {
    super.initState();
    final photos = widget.activity.photos;
    if (photos.isNotEmpty) {
      Supabase.instance.client.storage.from('run-photos').download(photos.first).then((b) {
        if (mounted) {
          setState(() {
            _photo = b;
            _style = _CardStyle.foto;
          });
        }
      }).catchError((Object _) {});
    }
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool(_prefKey);
      if (v != null && mounted) setState(() => _hideHome = v);
    }).catchError((_) {});
  }

  void _setHideHome(bool v) {
    setState(() => _hideHome = v);
    SharedPreferences.getInstance().then((p) => p.setBool(_prefKey, v)).catchError((_) => false);
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('De afbeelding kon niet worden gemaakt.');
      final a = widget.activity;
      final name = 'runwise-${a.startedAt.toLocal().toIso8601String().substring(0, 10)}.png';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png', name: name)],
        text: '${Fmt.km(a.distanceMeters, decimals: 1)} gelopen met RunWise 🏃',
      ));
    } catch (e) {
      if (mounted) showMessage(context, 'Delen is niet gelukt. Probeer het opnieuw.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deel je run')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Center(
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _key,
                      child: RunShareCard(
                        activity: widget.activity,
                        route: widget.route,
                        badges: widget.badges,
                        orange: _style == _CardStyle.oranje,
                        hideHome: _hideHome,
                        photo: _style == _CardStyle.foto ? _photo : null,
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
                  SegmentedButton<_CardStyle>(
                    segments: [
                      const ButtonSegment(value: _CardStyle.donker, label: Text('Donker')),
                      const ButtonSegment(value: _CardStyle.oranje, label: Text('Oranje')),
                      if (_photo != null) const ButtonSegment(value: _CardStyle.foto, label: Text('Foto')),
                    ],
                    selected: {_style},
                    onSelectionChanged: (s) => setState(() => _style = s.first),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _hideHome,
                    onChanged: _setHideHome,
                    title: const Text('Verberg waar je woont'),
                    subtitle: const Text('Laat de eerste en laatste 300 m van je route weg'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: RwColors.accentDark),
                          )
                        : const Icon(Icons.ios_share),
                    label: const Text('Delen of opslaan'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// De deelkaart zelf: 360 × 450 (wordt 1080 × 1350 px, het staande Instagram-formaat).
class RunShareCard extends StatelessWidget {
  const RunShareCard({
    super.key,
    required this.activity,
    this.route,
    this.badges = const [],
    this.orange = false,
    this.hideHome = true,
    this.photo,
  });
  final Activity activity;
  final RunRoute? route;
  final List<String> badges;
  final bool orange;

  /// Eigen foto als achtergrond (donker gemaakt zodat de tekst leesbaar blijft).
  final Uint8List? photo;

  /// Privacyzone: begin en eind van de route weglaten.
  final bool hideHome;

  /// Kop boven de afstand: record, of het verhaal van het weer.
  String? _headline() {
    if (badges.isNotEmpty) return badges.first.toUpperCase();
    final a = activity;
    final wind = a.windSpeedKmh ?? 0;
    final feels = a.feelsLikeCelsius ?? a.temperatureCelsius;
    if (wind >= 25) return 'DOOR ${wind.round()} KM/U WIND';
    if (feels != null && feels >= 25) return 'IN DE HITTE: ${feels.round()}°';
    if (feels != null && feels <= 0) return 'IN DE KOU: ${feels.round()}°';
    final h = a.startedAt.toLocal().hour;
    if (h < 7) return 'VROEGE VOGEL';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final fg = orange ? RwColors.accentDark : RwColors.text;
    final muted = orange ? RwColors.accentDark.withValues(alpha: 0.7) : RwColors.muted;
    final cost = weatherCost(a);
    final headline = _headline();
    final km = (a.distanceMeters / 1000).toStringAsFixed(2).replaceAll('.', ',');
    final weather = [
      if (a.temperatureCelsius != null) '${a.temperatureCelsius!.round()}°',
      if (a.windSpeedKmh != null) '${a.windSpeedKmh!.round()} km/u',
    ].join(' · ');
    // Liever het echte GPS-spoor van de run, anders de gekoppelde route.
    final line = a.hasTrack ? a.trackPolyline! : route?.polyline;
    final raw = line == null ? const <LatLng>[] : decodePolyline(line);
    final shown = hideHome ? trimPrivacyZone(raw, radius: 300) : raw;
    final track = shown.length < 2 ? null : RouteTrack(shown);

    return SizedBox(
      width: 360,
      height: 450,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: orange
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [RwColors.accentLight, RwColors.accent, RwColors.accentDeep],
                )
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF17171B), RwColors.background],
                ),
        ),
        child: Stack(
          children: [
            if (photo != null) ...[
              Positioned.fill(child: Image.memory(photo!, fit: BoxFit.cover)),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x99000000), Color(0x33000000), Color(0xE6000000)],
                    ),
                  ),
                ),
              ),
            ],
            if (!orange && photo == null)
              Positioned(
                right: -120,
                top: -120,
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [RwColors.accent.withValues(alpha: 0.28), RwColors.accent.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _tint(Image.asset('assets/logo/mark.png', height: 18), orange),
                      const SizedBox(width: 8),
                      _tint(Image.asset('assets/logo/wordmark.png', height: 12), orange),
                      const Spacer(),
                      Text(
                        Fmt.date(a.startedAt),
                        style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: track != null && track.isValid
                        ? CustomPaint(
                            size: Size.infinite,
                            painter: _ShareRoutePainter(
                              track: track,
                              windSpeed: a.windSpeedKmh,
                              windFrom: a.windDirectionDegrees,
                              orange: orange,
                              showStart: !hideHome,
                            ),
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Icon(Icons.directions_run, size: 90, color: fg.withValues(alpha: 0.12)),
                          ),
                  ),
                  const SizedBox(height: 10),
                  if (headline != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: orange ? RwColors.accentDark : RwColors.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        headline,
                        style: TextStyle(
                          color: orange ? RwColors.accent : RwColors.accentDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        km,
                        style: TextStyle(
                          fontFamily: RwFonts.display,
                          fontSize: 76,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: fg,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'km',
                        style: TextStyle(fontFamily: RwFonts.display, fontSize: 26, fontWeight: FontWeight.w800, color: fg),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _stat('TIJD', Fmt.duration(a.movingTimeSeconds), fg, muted),
                      _stat('TEMPO', Fmt.pace(a.paceSecondsPerKm).replaceAll(' /km', ''), fg, muted),
                      if (weather.isNotEmpty) _stat('WEER', weather, fg, muted),
                    ],
                  ),
                  if (cost.matters) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Bij ideaal loopweer: ${Fmt.duration(correctedSeconds(a))}',
                      style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (a.source == 'strava') ...[
                    const SizedBox(height: 4),
                    Text('Gegevens via Strava', style: TextStyle(color: muted, fontSize: 9)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _tint(Widget child, bool orange) => orange
      ? ColorFiltered(colorFilter: const ColorFilter.mode(RwColors.accentDark, BlendMode.srcIn), child: child)
      : child;

  static Widget _stat(String label, String value, Color fg, Color muted) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(fontFamily: RwFonts.display, fontSize: 20, fontWeight: FontWeight.w800, color: fg),
            ),
          ],
        ),
      );
}

/// Tekent de route als lijn, gekleurd op de wind tijdens de run.
class _ShareRoutePainter extends CustomPainter {
  _ShareRoutePainter({
    required this.track,
    required this.windSpeed,
    required this.windFrom,
    required this.orange,
    this.showStart = true,
  });
  final bool showStart;
  final RouteTrack track;
  final double? windSpeed;
  final double? windFrom;
  final bool orange;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = track.points;
    var minLat = pts.first.lat, maxLat = pts.first.lat, minLon = pts.first.lon, maxLon = pts.first.lon;
    for (final p in pts) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    final lonScale = math.cos(((minLat + maxLat) / 2) * math.pi / 180);
    final w = math.max((maxLon - minLon) * lonScale, 1e-9);
    final h = math.max(maxLat - minLat, 1e-9);
    const pad = 12.0;
    final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    // Links uitlijnen, verticaal centreren.
    final ox = pad;
    final oy = (size.height - h * scale) / 2;
    Offset map(LatLng p) => Offset(ox + (p.lon - minLon) * lonScale * scale, oy + (maxLat - p.lat) * scale);

    Path pathOf(List<LatLng> list) {
      final path = Path()..moveTo(map(list.first).dx, map(list.first).dy);
      for (final p in list.skip(1)) {
        final o = map(p);
        path.lineTo(o.dx, o.dy);
      }
      return path;
    }

    final full = pathOf(pts);
    final base = orange ? RwColors.accentDark : RwColors.accent;
    canvas.drawPath(
      full,
      Paint()
        ..color = base.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final segments = orange
        ? [WindSegment(pts, WindClass.calm)]
        : windSegments(track, windSpeedKmh: windSpeed ?? 0, windFromDegrees: windSpeed == null ? null : windFrom);
    for (final s in segments) {
      if (s.points.length < 2) continue;
      canvas.drawPath(
        pathOf(s.points),
        Paint()
          ..color = orange ? RwColors.accentDark : windColor(s.windClass)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (showStart) {
      final start = map(pts.first);
      canvas.drawCircle(start, 7, Paint()..color = orange ? RwColors.accentDark : RwColors.text);
      canvas.drawCircle(start, 3, Paint()..color = orange ? RwColors.accent : RwColors.background);
    }
  }

  @override
  bool shouldRepaint(covariant _ShareRoutePainter old) => old.track != track || old.orange != orange || old.showStart != showStart;
}

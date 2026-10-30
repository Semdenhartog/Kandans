import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/geo.dart';
import '../../domain/poster_map.dart';
import '../../domain/route_geometry.dart';

/// Achtergrondtextuur van een posterstijl.
enum PosterTexture { none, marble, grid, topo }

/// Een posterstijl. De stijlen met [isLuxe] horen bij de Luxe-ontwerpen (losse aankoop, gratis bij Premium).
enum PosterStyle {
  nacht('Nacht', [Color(0xFF0E0E12), Color(0xFF0E0E12)], Color(0xFFF5F5F7), Color(0xFFFF7A1A)),
  zand('Zand', [Color(0xFFF1E9DC), Color(0xFFF1E9DC)], Color(0xFF1E1B18), Color(0xFFC2410C)),
  bos('Bos', [Color(0xFF12261C), Color(0xFF12261C)], Color(0xFFEAF4EC), Color(0xFFFFB547)),
  goud('Goud', [Color(0xFF17120A), Color(0xFF070605)], Color(0xFFF4E7C5), Color(0xFFD9B45A),
      isLuxe: true, frame: Color(0xFFD9B45A), goldText: true, glow: true),
  marmer('Marmer', [Color(0xFFF6F4EF), Color(0xFFE9E5DC)], Color(0xFF1F1D1A), Color(0xFF2B2824),
      isLuxe: true, frame: Color(0xFFB8964A), texture: PosterTexture.marble),
  topo('Topo', [Color(0xFFF0E9DB), Color(0xFFE5DAC6)], Color(0xFF2A2620), Color(0xFF8A3B1E),
      isLuxe: true, frame: Color(0xFF8A7A5C), texture: PosterTexture.topo),
  oceaan('Oceaan', [Color(0xFF0B3B5C), Color(0xFF041A2B)], Color(0xFFE6F6FB), Color(0xFF7DE3F4),
      isLuxe: true, glow: true),
  blauwdruk('Blauwdruk', [Color(0xFF0F4C81), Color(0xFF0B3A63)], Color(0xFFF2F7FC), Color(0xFFFFFFFF),
      isLuxe: true, texture: PosterTexture.grid);

  const PosterStyle(
    this.label,
    this.background,
    this.fg,
    this.line, {
    this.isLuxe = false,
    this.frame,
    this.goldText = false,
    this.glow = false,
    this.texture = PosterTexture.none,
  });

  final String label;

  /// Verloop van boven naar onder.
  final List<Color> background;
  final Color fg;
  final Color line;
  final bool isLuxe;

  /// Dunne dubbele lijst rondom (bijv. goud).
  final Color? frame;

  /// Titel en cijfers met een gouden verloop.
  final bool goldText;

  /// Zachte gloed onder de routelijn.
  final bool glow;
  final PosterTexture texture;

  /// Kleur voor sierlijnen.
  Color get accent => frame ?? line;
}

/// De cijfers en keuzes op de poster.
class PosterData {
  const PosterData({
    required this.title,
    required this.polyline,
    required this.distanceMeters,
    this.elevationGainMeters,
    this.fastestSeconds,
    this.timesRun = 0,
    this.subtitle,
    this.elevation = const [],
    this.startLat,
    this.startLon,
    this.showElevation = true,
    this.showKm = true,
    this.showCoords = true,
    this.mapLines = const [],
    this.showMap = true,
  });

  final String title;
  final String polyline;
  final double distanceMeters;
  final double? elevationGainMeters;
  final int? fastestSeconds;
  final int timesRun;

  /// Kleine regel onder de titel (bijv. plaats en datum of een eigen tekst).
  final String? subtitle;

  /// Hoogteprofiel langs de route (voor de strook onder de lijn).
  final List<ElevationSample> elevation;
  final double? startLat;
  final double? startLon;

  final bool showElevation;
  final bool showKm;
  final bool showCoords;

  /// Straten, water en spoor rond de route (OpenStreetMap), zacht onder de lijn.
  final List<MapLine> mapLines;
  final bool showMap;
}

/// Coördinaten van de start, zoals op een kaart: "52.1528° N · 5.6034° O".
String posterCoordinates(double lat, double lon) {
  final ns = lat >= 0 ? 'N' : 'Z';
  final eo = lon >= 0 ? 'O' : 'W';
  return '${lat.abs().toStringAsFixed(4)}° $ns  ·  ${lon.abs().toStringAsFixed(4)}° $eo';
}

/// De poster zelf, op elke maat. Alles schaalt mee met de breedte, zodat dezelfde poster
/// op het scherm (klein) en voor de drukker (groot) er hetzelfde uitziet.
class RoutePosterArt extends StatelessWidget {
  const RoutePosterArt({super.key, required this.data, required this.style});
  final PosterData data;
  final PosterStyle style;

  @override
  Widget build(BuildContext context) {
    // Een poster is een vast ontwerp: niet meeschalen met de lettergrootte van de telefoon.
    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(builder: (context, c) {
        // Ontworpen op 360 breed; daarna geschaald.
        final u = c.maxWidth / 360;
        final s = style;
        Widget gold(Widget child) => s.goldText
            ? ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF3DC95), Color(0xFFD9B45A), Color(0xFF9C7A2E), Color(0xFFE8C977)],
                  stops: [0, 0.4, 0.75, 1],
                ).createShader(r),
                child: child,
              )
            : child;

        Widget stat(String label, String value) => Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(fit: BoxFit.scaleDown, child: gold(Text(value,
                  maxLines: 1,
                  style: TextStyle(
                      color: s.fg, fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 18 * u, fontWeight: FontWeight.w700, height: 1.1)))),
              SizedBox(height: 3 * u),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label.toUpperCase(),
                    maxLines: 1,
                    style: TextStyle(color: s.fg.withValues(alpha: 0.55), fontSize: 7 * u, letterSpacing: 1.8 * u, fontWeight: FontWeight.w600)),
              ),
            ]);

        Widget divider() => Container(width: 0.6 * u, height: 26 * u, color: s.fg.withValues(alpha: 0.22));

        final pts = decodePolyline(data.polyline);
        final lat = data.startLat ?? (pts.isEmpty ? null : pts.first.lat);
        final lon = data.startLon ?? (pts.isEmpty ? null : pts.first.lon);
        final ele = data.showElevation && data.elevation.length >= 2 ? data.elevation : null;
        final third = data.fastestSeconds != null
            ? stat('Snelste', Fmt.duration(data.fastestSeconds!))
            : stat('Gelopen', '${data.timesRun}×');
        // Met een snelste tijd ook het tempo erbij (zonder "/km", dat staat in het label).
        final pace = data.fastestSeconds != null && data.distanceMeters > 200
            ? stat('Tempo /km', Fmt.pace(data.fastestSeconds! / (data.distanceMeters / 1000)).replaceAll(' /km', ''))
            : null;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: s.background),
          ),
          child: Stack(children: [
            if (s.texture != PosterTexture.none) Positioned.fill(child: CustomPaint(painter: _TexturePainter(s.texture, u, s.fg))),
            Positioned.fill(child: CustomPaint(painter: _GrainPainter(u, s.fg))),
            if (s.frame != null) ...[
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(11 * u),
                  child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: s.frame!.withValues(alpha: 0.85), width: 1.1 * u))),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(15 * u),
                  child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: s.frame!.withValues(alpha: 0.45), width: 0.5 * u))),
                ),
              ),
            ],
            Padding(
              padding: EdgeInsets.fromLTRB(30 * u, 28 * u, 30 * u, 22 * u),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (data.showCoords && lat != null && lon != null)
                  Text(posterCoordinates(lat, lon),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                          color: s.fg.withValues(alpha: 0.5), fontFeatures: rwTnum, fontSize: 7.5 * u, letterSpacing: 1.6 * u, fontWeight: FontWeight.w500)),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 14 * u),
                    child: CustomPaint(
                      painter: PosterRoutePainter(
                        pts,
                        color: s.line,
                        width: 3.6 * u,
                        glow: s.glow,
                        background: s.background.last,
                        kmMarkers: data.showKm,
                        u: u,
                        mapLines: data.showMap ? data.mapLines : const [],
                        mapColor: s.fg,
                        labelColor: s.fg,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
                if (ele != null) ...[
                  SizedBox(
                    height: 30 * u,
                    child: CustomPaint(painter: _ElevationStripPainter(ele, color: s.line, text: s.fg, u: u), size: Size.infinite),
                  ),
                  SizedBox(height: 14 * u),
                ],
                gold(Text(data.title.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: s.fg, fontFamily: RwFonts.display, fontSize: 25 * u, fontWeight: FontWeight.w800, height: 1.08, letterSpacing: 2.6 * u))),
                if (data.subtitle != null && data.subtitle!.trim().isNotEmpty) ...[
                  SizedBox(height: 5 * u),
                  Text(data.subtitle!.trim().toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: s.fg.withValues(alpha: 0.6), fontSize: 8 * u, letterSpacing: 2.4 * u, fontWeight: FontWeight.w600)),
                ],
                // Sierlijn met een ruitje in het midden.
                Padding(
                  padding: EdgeInsets.fromLTRB(80 * u, 11 * u, 80 * u, 12 * u),
                  child: Row(children: [
                    Expanded(child: Container(height: 0.6 * u, color: s.accent.withValues(alpha: 0.7))),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 7 * u),
                      child: Transform.rotate(
                        angle: math.pi / 4,
                        child: Container(width: 4.5 * u, height: 4.5 * u, color: s.accent),
                      ),
                    ),
                    Expanded(child: Container(height: 0.6 * u, color: s.accent.withValues(alpha: 0.7))),
                  ]),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Expanded(child: stat('Afstand', Fmt.km(data.distanceMeters, decimals: 1))),
                  divider(),
                  Expanded(child: stat('Hoogtemeters', data.elevationGainMeters == null ? '–' : '${data.elevationGainMeters!.round()} m')),
                  divider(),
                  Expanded(child: third),
                  if (pace != null) ...[divider(), Expanded(child: pace)],
                ]),
                SizedBox(height: 16 * u),
                Text('K A D A N S',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: s.fg.withValues(alpha: 0.45), fontFamily: RwFonts.display, fontSize: 7.5 * u, fontWeight: FontWeight.w700, letterSpacing: 2 * u)),
              ]),
            ),
          ]),
        );
      }),
    );
  }
}

/// Routelijn voor de poster: past in het vak, ronde hoeken, eventueel met gloed,
/// een open rondje bij de start, een stip bij de finish en (als gewenst) kilometerpunten.
class PosterRoutePainter extends CustomPainter {
  PosterRoutePainter(
    this.points, {
    required this.color,
    required this.width,
    this.glow = false,
    this.background = const Color(0xFF000000),
    this.kmMarkers = false,
    this.u = 1,
    this.mapLines = const [],
    this.mapColor = const Color(0xFFFFFFFF),
    this.labelColor,
  });
  final List<LatLng> points;
  final List<MapLine> mapLines;
  final Color mapColor;

  /// Kleur voor de woordjes START en FINISH; zonder kleur geen woordjes.
  final Color? labelColor;
  final Color color;
  final double width;
  final bool glow;
  final Color background;
  final bool kmMarkers;
  final double u;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;
    var minLat = points.first.lat, maxLat = minLat, minLon = points.first.lon, maxLon = minLon;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    final lonScale = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final w = math.max((maxLon - minLon) * lonScale, 1e-9);
    final h = math.max(maxLat - minLat, 1e-9);
    final pad = width * 3;
    final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;
    Offset at(LatLng p) => Offset(ox + (p.lon - minLon) * lonScale * scale, oy + (maxLat - p.lat) * scale);

    if (mapLines.isNotEmpty) _paintMap(canvas, size, at);

    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (final p in points.skip(1)) {
      final o = at(p);
      path.lineTo(o.dx, o.dy);
    }
    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 2),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Kilometerpunten: elke km (tot 21 km), elke 5 km (tot 60 km).
    if (kmMarkers) {
      var total = 0.0;
      for (var i = 1; i < points.length; i++) {
        total += distanceMeters(points[i - 1], points[i]);
      }
      final step = total <= 21500 ? 1000.0 : (total <= 60000 ? 5000.0 : 0.0);
      if (step > 0) {
        final r = 5.2 * u;
        var next = step, run = 0.0;
        for (var i = 1; i < points.length && next < total - step * 0.4; i++) {
          final d = distanceMeters(points[i - 1], points[i]);
          while (d > 0 && run + d >= next && next < total - step * 0.4) {
            final t = (next - run) / d;
            final a = at(points[i - 1]), b = at(points[i]);
            final o = Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
            canvas.drawCircle(o, r, Paint()..color = background);
            canvas.drawCircle(
              o,
              r,
              Paint()
                ..color = color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.9 * u,
            );
            final tp = TextPainter(
              text: TextSpan(
                text: '${(next / 1000).round()}',
                style: TextStyle(color: color, fontSize: 5.2 * u, fontWeight: FontWeight.w800, fontFamily: RwFonts.display, height: 1),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
            next += step;
          }
          run += d;
        }
      }
    }

    // Start (open rondje) en finish (stip). Bij een rondje vallen ze samen: rondje met stip.
    final start = at(points.first), end = at(points.last);
    final ring = width * 1.7;
    if ((start - end).distance > ring * 2.2) {
      canvas.drawCircle(end, ring * 0.85, Paint()..color = color);
    }
    canvas.drawCircle(start, ring, Paint()..color = background);
    canvas.drawCircle(
      start,
      ring,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 0.55,
    );
    final loop = (start - end).distance <= ring * 2.2;
    if (loop) canvas.drawCircle(start, ring * 0.4, Paint()..color = color);

    // START en FINISH als klein label, zoals op een wedstrijdkaart.
    if (labelColor != null) {
      void tag(String text, Offset at) {
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(color: labelColor!.withValues(alpha: 0.75), fontSize: 5.4 * u, fontWeight: FontWeight.w700, letterSpacing: 1.2 * u, height: 1),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Rechts van de markering; past dat niet, dan links.
        var x = at.dx + ring + 4 * u;
        if (x + tp.width > size.width) x = at.dx - ring - 4 * u - tp.width;
        tp.paint(canvas, Offset(x, at.dy - tp.height / 2));
      }

      if (loop) {
        tag('START · FINISH', start);
      } else {
        tag('START', start);
        tag('FINISH', end);
      }
    }
  }

  /// De kaart onder de route: water, paden, spoor en straten, met zachte randen die in de poster overlopen.
  void _paintMap(Canvas canvas, Size size, Offset Function(LatLng) at) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    canvas.clipRect(rect);
    final byKind = <MapLineKind, Path>{};
    for (final l in mapLines) {
      final p = byKind.putIfAbsent(l.kind, Path.new);
      final first = at(l.points.first);
      p.moveTo(first.dx, first.dy);
      for (final q in l.points.skip(1)) {
        final o = at(q);
        p.lineTo(o.dx, o.dy);
      }
      if (l.kind == MapLineKind.waterArea) p.close();
    }
    Paint stroke(Color c, double alpha, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..color = c.withValues(alpha: alpha)
      ..strokeWidth = w * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Van onder naar boven: water, paden, spoor, straten, doorgaande wegen.
    const order = [MapLineKind.waterArea, MapLineKind.water, MapLineKind.path, MapLineKind.rail, MapLineKind.minor, MapLineKind.major];
    for (final kind in order) {
      final p = byKind[kind];
      if (p == null) continue;
      switch (kind) {
        case MapLineKind.waterArea:
          canvas.drawPath(p, Paint()..color = mapColor.withValues(alpha: 0.07));
        case MapLineKind.water:
          canvas.drawPath(p, stroke(mapColor, 0.2, 1.4));
        case MapLineKind.path:
          canvas.drawPath(p, stroke(mapColor, 0.09, 0.35));
        case MapLineKind.rail:
          canvas.drawPath(p, stroke(mapColor, 0.15, 0.5));
        case MapLineKind.minor:
          canvas.drawPath(p, stroke(mapColor, 0.16, 0.55));
        case MapLineKind.major:
          canvas.drawPath(p, stroke(mapColor, 0.25, 1.0));
      }
    }
    // Zachte randen: de kaart loopt naar alle kanten weg, ook waar de kaartgegevens ophouden.
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final l in mapLines) {
      for (final q in l.points) {
        final o = at(q);
        minX = math.min(minX, o.dx);
        maxX = math.max(maxX, o.dx);
        minY = math.min(minY, o.dy);
        maxY = math.max(maxY, o.dy);
      }
    }
    final area = Rect.fromLTRB(math.max(minX, 0), math.max(minY, 0), math.min(maxX, size.width), math.min(maxY, size.height));
    if (!area.isEmpty) {
      const fade = [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)];
      const stops = [0.0, 0.2, 0.8, 1.0];
      canvas.drawRect(
          rect,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = ui.Gradient.linear(area.centerLeft, area.centerRight, fade, stops));
      canvas.drawRect(
          rect,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = ui.Gradient.linear(area.topCenter, area.bottomCenter, fade, stops));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PosterRoutePainter old) =>
      old.points != points ||
      old.color != color ||
      old.width != width ||
      old.glow != glow ||
      old.background != background ||
      old.kmMarkers != kmMarkers ||
      old.mapLines != mapLines ||
      old.mapColor != mapColor ||
      old.labelColor != labelColor ||
      old.u != u;
}

/// Smalle strook met het hoogteprofiel, met de hoogste en laagste meter erbij.
class _ElevationStripPainter extends CustomPainter {
  _ElevationStripPainter(this.samples, {required this.color, required this.text, required this.u});
  final List<ElevationSample> samples;
  final Color color;
  final Color text;
  final double u;

  @override
  void paint(Canvas canvas, Size size) {
    final first = samples.first.meters, last = samples.last.meters;
    final span = math.max(last - first, 1.0);
    var lo = samples.first.ele, hi = lo;
    for (final s in samples) {
      lo = math.min(lo, s.ele);
      hi = math.max(hi, s.ele);
    }
    // Minstens 20 m bereik, anders lijkt een vlak rondje een berg.
    final mid = (lo + hi) / 2;
    final range = math.max(hi - lo, 20.0);
    final bottom = mid - range / 2;
    final labelW = 26 * u;
    final w = size.width - labelW;
    Offset at(ElevationSample s) =>
        Offset(labelW + (s.meters - first) / span * w, size.height - (s.ele - bottom) / range * (size.height - 2 * u) - 1 * u);

    final line = Path()..moveTo(at(samples.first).dx, at(samples.first).dy);
    for (final s in samples.skip(1)) {
      final o = at(s);
      line.lineTo(o.dx, o.dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(labelW, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, size.height), [color.withValues(alpha: 0.32), color.withValues(alpha: 0.02)]),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9 * u
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawLine(
      Offset(labelW, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = text.withValues(alpha: 0.25)
        ..strokeWidth = 0.5 * u,
    );

    void label(String s, double y) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(color: text.withValues(alpha: 0.5), fontSize: 5.6 * u, fontFeatures: rwTnum, fontWeight: FontWeight.w600, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(labelW - 4 * u - tp.width, y - tp.height / 2));
    }

    label('${hi.round()} m', at(ElevationSample(first, hi)).dy);
    label('${lo.round()} m', at(ElevationSample(first, lo)).dy);
  }

  @override
  bool shouldRepaint(_ElevationStripPainter old) => old.samples != samples || old.color != color || old.u != u;
}

/// Heel fijne papierkorrel, altijd hetzelfde (vaste startwaarde).
class _GrainPainter extends CustomPainter {
  _GrainPainter(this.u, this.fg);
  final double u;
  final Color fg;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(11);
    final n = (size.width * size.height / (16 * u * u)).clamp(0, 6000).toInt();
    final pts = [for (var i = 0; i < n; i++) Offset(r.nextDouble() * size.width, r.nextDouble() * size.height)];
    canvas.drawPoints(
      ui.PointMode.points,
      pts,
      Paint()
        ..color = fg.withValues(alpha: 0.05)
        ..strokeWidth = 0.8 * u
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.u != u || old.fg != fg;
}

/// Marmeraders, een blauwdruk-raster of hoogtelijnen, altijd hetzelfde (vaste startwaarde), zodat de poster
/// op het scherm en bij de drukker gelijk is.
class _TexturePainter extends CustomPainter {
  _TexturePainter(this.texture, this.u, this.fg);
  final PosterTexture texture;
  final double u;
  final Color fg;

  @override
  void paint(Canvas canvas, Size size) {
    switch (texture) {
      case PosterTexture.none:
        return;
      case PosterTexture.grid:
        final thin = Paint()
          ..color = Colors.white.withValues(alpha: 0.07)
          ..strokeWidth = 0.6 * u;
        final thick = Paint()
          ..color = Colors.white.withValues(alpha: 0.14)
          ..strokeWidth = 1 * u;
        final step = 18 * u;
        var i = 0;
        for (var x = 0.0; x <= size.width; x += step, i++) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 5 == 0 ? thick : thin);
        }
        i = 0;
        for (var y = 0.0; y <= size.height; y += step, i++) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), i % 5 == 0 ? thick : thin);
        }
      case PosterTexture.topo:
        // Hoogtelijnen rond een paar "heuvels", zoals op een stafkaart.
        final r = math.Random(5);
        final hills = [
          Offset(size.width * 0.18, size.height * 0.22),
          Offset(size.width * 0.86, size.height * 0.5),
          Offset(size.width * 0.3, size.height * 0.9),
        ];
        for (final c in hills) {
          final phases = [for (var k = 0; k < 3; k++) r.nextDouble() * math.pi * 2];
          for (var ring = 1; ring <= 11; ring++) {
            final base = ring * 17.0 * u;
            final path = Path();
            for (var a = 0; a <= 90; a++) {
              final t = a / 90 * math.pi * 2;
              final wobble = 1 +
                  0.16 * math.sin(2 * t + phases[0]) +
                  0.09 * math.sin(3 * t + phases[1] + ring * 0.25) +
                  0.05 * math.sin(5 * t + phases[2]);
              final p = c + Offset(math.cos(t), math.sin(t) * 0.82) * base * wobble;
              if (a == 0) {
                path.moveTo(p.dx, p.dy);
              } else {
                path.lineTo(p.dx, p.dy);
              }
            }
            canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..color = fg.withValues(alpha: ring % 5 == 0 ? 0.13 : 0.07)
                ..strokeWidth = (ring % 5 == 0 ? 0.9 : 0.55) * u,
            );
          }
        }
      case PosterTexture.marble:
        final r = math.Random(7);
        for (var v = 0; v < 16; v++) {
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFF8C8578).withValues(alpha: 0.08 + r.nextDouble() * 0.16)
            ..strokeWidth = (0.4 + r.nextDouble() * 1.8) * u;
          var p = Offset(r.nextDouble() * size.width * 1.2 - size.width * 0.1, r.nextDouble() * size.height);
          final path = Path()..moveTo(p.dx, p.dy);
          final angle = -0.6 + r.nextDouble() * 0.5;
          for (var k = 0; k < 6; k++) {
            final len = (40 + r.nextDouble() * 90) * u;
            final next = p + Offset(math.cos(angle) * len, math.sin(angle) * len + (r.nextDouble() - 0.5) * 40 * u);
            final ctrl = Offset((p.dx + next.dx) / 2 + (r.nextDouble() - 0.5) * 50 * u, (p.dy + next.dy) / 2 + (r.nextDouble() - 0.5) * 50 * u);
            path.quadraticBezierTo(ctrl.dx, ctrl.dy, next.dx, next.dy);
            p = next;
          }
          canvas.drawPath(path, paint);
        }
    }
  }

  @override
  bool shouldRepaint(_TexturePainter old) => old.texture != texture || old.u != u || old.fg != fg;
}

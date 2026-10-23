import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/geo.dart';

/// Achtergrondtextuur van een posterstijl.
enum PosterTexture { none, marble, grid }

/// Een posterstijl. De stijlen met [isLuxe] horen bij de Luxe-ontwerpen (losse aankoop, gratis bij Premium).
enum PosterStyle {
  nacht('Nacht', [Color(0xFF0E0E12), Color(0xFF0E0E12)], Color(0xFFF5F5F7), Color(0xFFFF7A1A)),
  zand('Zand', [Color(0xFFF1E9DC), Color(0xFFF1E9DC)], Color(0xFF1E1B18), Color(0xFFC2410C)),
  bos('Bos', [Color(0xFF12261C), Color(0xFF12261C)], Color(0xFFEAF4EC), Color(0xFFFFB547)),
  goud('Goud', [Color(0xFF17120A), Color(0xFF070605)], Color(0xFFF4E7C5), Color(0xFFD9B45A),
      isLuxe: true, frame: Color(0xFFD9B45A), goldText: true, glow: true),
  marmer('Marmer', [Color(0xFFF6F4EF), Color(0xFFE9E5DC)], Color(0xFF1F1D1A), Color(0xFF2B2824),
      isLuxe: true, frame: Color(0xFFB8964A), texture: PosterTexture.marble),
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

  /// Dunne lijst rondom (bijv. goud).
  final Color? frame;

  /// Titel en cijfers met een gouden verloop.
  final bool goldText;

  /// Zachte gloed onder de routelijn.
  final bool glow;
  final PosterTexture texture;
}

/// De cijfers op de poster.
class PosterData {
  const PosterData({
    required this.title,
    required this.polyline,
    required this.distanceMeters,
    this.elevationGainMeters,
    this.fastestSeconds,
    this.timesRun = 0,
    this.subtitle,
  });

  final String title;
  final String polyline;
  final double distanceMeters;
  final double? elevationGainMeters;
  final int? fastestSeconds;
  final int timesRun;

  /// Kleine regel onder de titel (bijv. plaats of datum).
  final String? subtitle;
}

/// De poster zelf, op elke maat. Alles schaalt mee met de breedte, zodat dezelfde poster
/// op het scherm (klein) en voor de drukker (groot) er hetzelfde uitziet.
class RoutePosterArt extends StatelessWidget {
  const RoutePosterArt({super.key, required this.data, required this.style});
  final PosterData data;
  final PosterStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
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

      Widget stat(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(),
                style: TextStyle(color: s.fg.withValues(alpha: 0.55), fontSize: 10 * u, letterSpacing: 1.6 * u, fontWeight: FontWeight.w600)),
            SizedBox(height: 3 * u),
            gold(Text(value,
                maxLines: 1,
                style: TextStyle(color: s.fg, fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 24 * u, fontWeight: FontWeight.w800))),
          ]);

      final pts = decodePolyline(data.polyline);
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: s.background),
        ),
        child: Stack(children: [
          if (s.texture != PosterTexture.none) Positioned.fill(child: CustomPaint(painter: _TexturePainter(s.texture, u))),
          if (s.frame != null)
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(12 * u),
                child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: s.frame!.withValues(alpha: 0.8), width: 1 * u))),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(30 * u, 34 * u, 30 * u, 26 * u),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              gold(Text(data.title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: s.fg, fontFamily: RwFonts.display, fontSize: 30 * u, fontWeight: FontWeight.w800, height: 1.05))),
              if (data.subtitle != null) ...[
                SizedBox(height: 4 * u),
                Text(data.subtitle!, style: TextStyle(color: s.fg.withValues(alpha: 0.6), fontSize: 11 * u, letterSpacing: 0.6 * u)),
              ],
              SizedBox(height: 8 * u),
              Align(alignment: Alignment.centerLeft, child: Container(height: 3 * u, width: 48 * u, color: s.frame ?? s.line)),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 22 * u),
                  child: CustomPaint(painter: PosterRoutePainter(pts, color: s.line, width: 4.5 * u, glow: s.glow), size: Size.infinite),
                ),
              ),
              Row(children: [
                Expanded(child: stat('Afstand', Fmt.km(data.distanceMeters, decimals: 1))),
                Expanded(child: stat('Hoogte', data.elevationGainMeters == null ? '–' : '${data.elevationGainMeters!.round()} m')),
                Expanded(
                  child: data.fastestSeconds != null
                      ? stat('Snelste', Fmt.duration(data.fastestSeconds!))
                      : stat('Gelopen', '${data.timesRun}×'),
                ),
              ]),
              SizedBox(height: 18 * u),
              Row(children: [
                gold(Text('RUNWISE',
                    style: TextStyle(
                        color: s.fg.withValues(alpha: 0.7),
                        fontFamily: RwFonts.display,
                        fontSize: 13 * u,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3 * u))),
                const Spacer(),
                Text('loop op het beste moment', style: TextStyle(color: s.fg.withValues(alpha: 0.45), fontSize: 10 * u)),
              ]),
            ]),
          ),
        ]),
      );
    });
  }
}

/// Routelijn voor de poster: past in het vak, ronde hoeken, eventueel met gloed.
class PosterRoutePainter extends CustomPainter {
  PosterRoutePainter(this.points, {required this.color, required this.width, this.glow = false});
  final List<LatLng> points;
  final Color color;
  final double width;
  final bool glow;

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
    final pad = width * 2;
    final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;
    Offset at(LatLng p) => Offset(ox + (p.lon - minLon) * lonScale * scale, oy + (maxLat - p.lat) * scale);

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
    final start = at(points.first);
    canvas.drawCircle(start, width * 1.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(PosterRoutePainter old) =>
      old.points != points || old.color != color || old.width != width || old.glow != glow;
}

/// Marmeraders of een blauwdruk-raster, altijd hetzelfde (vaste startwaarde), zodat de poster
/// op het scherm en bij de drukker gelijk is.
class _TexturePainter extends CustomPainter {
  _TexturePainter(this.texture, this.u);
  final PosterTexture texture;
  final double u;

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
  bool shouldRepaint(_TexturePainter old) => old.texture != texture || old.u != u;
}

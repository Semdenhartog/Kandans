import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/geo.dart';
import '../../domain/route_geometry.dart';
import '../../shared/art/tilt.dart';

/// Schuin 3D-beeld van een route, zonder kaarttegels: het spoor ligt op een "tafel" in perspectief,
/// met de hoogte als een gouden wand eronder. Draait een fractie mee als je de telefoon kantelt.
/// Bovenaan Route-details; tikken opent "Vlieg over de route".
class RouteRelief extends StatefulWidget {
  const RouteRelief({super.key, required this.polyline, this.profile = const [], this.onTap, this.height = 210});
  final String polyline;
  final List<ElevationSample> profile;
  final VoidCallback? onTap;
  final double height;

  @override
  State<RouteRelief> createState() => _RouteReliefState();
}

class _RouteReliefState extends State<RouteRelief> {
  late List<LatLng> _track = decodePolyline(widget.polyline);

  @override
  void didUpdateWidget(RouteRelief old) {
    super.didUpdateWidget(old);
    if (old.polyline != widget.polyline) _track = decodePolyline(widget.polyline);
  }

  @override
  Widget build(BuildContext context) {
    if (_track.length < 2) return const SizedBox.shrink();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dark = RwColors.isDark;
    return Semantics(
      button: widget.onTap != null,
      label: 'Route in 3D. Tik om over de route te vliegen.',
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RwRadius.l),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark
                  ? const [Color(0xFF1C1712), Color(0xFF2C241C)]
                  : const [Color(0xFF2C241C), Color(0xFF4A3B2B)],
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 12))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: still ? 1 : 0, end: 1),
                  duration: const Duration(milliseconds: 1400),
                  curve: Curves.easeInOutCubic,
                  builder: (_, grow, _) => still
                      ? CustomPaint(painter: RouteReliefPainter(_track, widget.profile, grow: 1, yaw: 0))
                      : AnimatedBuilder(
                          animation: Tilt.instance,
                          builder: (_, _) => CustomPaint(
                            painter: RouteReliefPainter(_track, widget.profile, grow: grow, yaw: Tilt.instance.value.dx * 0.18),
                          ),
                        ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              top: 14,
              child: Text('ROUTE IN 3D',
                  style: TextStyle(fontFamily: 'KadansMono', fontSize: 11, letterSpacing: 1.6, color: Colors.white.withValues(alpha: 0.7))),
            ),
            if (widget.onTap != null)
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFD9BF92), borderRadius: BorderRadius.circular(RwRadius.s)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.flight_takeoff, size: 15, color: Color(0xFF211A14)),
                    SizedBox(width: 6),
                    Text('Vlieg over', style: TextStyle(color: Color(0xFF211A14), fontWeight: FontWeight.w700, fontSize: 12)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class RouteReliefPainter extends CustomPainter {
  RouteReliefPainter(this.track, this.profile, {required this.grow, required this.yaw});
  final List<LatLng> track;
  final List<ElevationSample> profile;
  final double grow;
  final double yaw;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0 || track.length < 2) return;
    // Platte coördinaten in meters rond het midden.
    final lat0 = track.map((p) => p.lat).reduce((a, b) => a + b) / track.length;
    final lon0 = track.map((p) => p.lon).reduce((a, b) => a + b) / track.length;
    final kx = 111320 * math.cos(lat0 * math.pi / 180);
    const ky = 110540.0;
    final flat = [for (final p in track) Offset((p.lon - lon0) * kx, -(p.lat - lat0) * ky)];
    var extent = 1.0;
    for (final o in flat) {
      extent = math.max(extent, math.max(o.dx.abs(), o.dy.abs()));
    }

    // Afstand langs de route → hoogte (uit het profiel, of de hoogte in de punten).
    final cum = <double>[0];
    for (var i = 1; i < track.length; i++) {
      cum.add(cum.last + (flat[i] - flat[i - 1]).distance);
    }
    double? eleAt(int i) {
      if (profile.length >= 2) {
        final m = cum[i] / (cum.last <= 0 ? 1 : cum.last) * profile.last.meters;
        var j = 1;
        while (j < profile.length - 1 && profile[j].meters < m) {
          j++;
        }
        final a = profile[j - 1], b = profile[j];
        final span = b.meters - a.meters;
        final f = span <= 0 ? 0.0 : ((m - a.meters) / span).clamp(0.0, 1.0);
        return a.ele + (b.ele - a.ele) * f;
      }
      return track[i].ele;
    }

    final eles = [for (var i = 0; i < track.length; i++) eleAt(i)];
    final known = eles.whereType<double>().toList();
    final minE = known.isEmpty ? 0.0 : known.reduce(math.min);
    final maxE = known.isEmpty ? 0.0 : known.reduce(math.max);
    final eSpan = math.max(maxE - minE, 15.0); // vlak Nederland: niet overdrijven

    // Perspectief: draai om de verticale as (yaw), kantel naar achteren, verder weg = kleiner.
    const pitch = 1.0; // ~57°
    final rot = -0.35 + yaw;
    final cr = math.cos(rot), sr = math.sin(rot);
    final scale = math.min(w, h * 1.6) * 0.42 / extent;
    Offset project(Offset p, double up) {
      final x = p.dx * cr - p.dy * sr;
      final y = p.dx * sr + p.dy * cr;
      final depth = y * math.sin(pitch);
      final persp = 1 / (1 + depth / (extent * 3.2));
      return Offset(w / 2 + x * scale * persp, h * 0.58 + (y * math.cos(pitch)) * scale * persp - up * persp);
    }

    // Raster op de "tafel".
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var g = -4; g <= 4; g++) {
      final v = g / 4 * extent * 1.25;
      canvas.drawLine(project(Offset(v, -extent * 1.25), 0), project(Offset(v, extent * 1.25), 0), grid);
      canvas.drawLine(project(Offset(-extent * 1.25, v), 0), project(Offset(extent * 1.25, v), 0), grid);
    }

    final n = (track.length * grow).clamp(2, track.length).toInt();
    final maxUp = h * 0.16;
    double upOf(int i) => eles[i] == null ? 0 : ((eles[i]! - minE) / eSpan) * maxUp * grow;

    // Schaduw op de tafel.
    final shadow = Path();
    for (var i = 0; i < n; i++) {
      final q = project(flat[i], 0);
      i == 0 ? shadow.moveTo(q.dx, q.dy) : shadow.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(
        shadow,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

    // Gouden wand (hoogte) van de tafel naar het spoor.
    if (known.isNotEmpty) {
      for (var i = 1; i < n; i++) {
        final a0 = project(flat[i - 1], 0), b0 = project(flat[i], 0);
        final a1 = project(flat[i - 1], upOf(i - 1)), b1 = project(flat[i], upOf(i));
        final wall = Path()
          ..moveTo(a0.dx, a0.dy)
          ..lineTo(b0.dx, b0.dy)
          ..lineTo(b1.dx, b1.dy)
          ..lineTo(a1.dx, a1.dy)
          ..close();
        canvas.drawPath(wall, Paint()..color = const Color(0xFFD9BF92).withValues(alpha: 0.16));
      }
    }

    // Het spoor zelf.
    final line = Path();
    for (var i = 0; i < n; i++) {
      final q = project(flat[i], upOf(i));
      i == 0 ? line.moveTo(q.dx, q.dy) : line.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(
        line,
        Paint()
          ..color = const Color(0xFFE9D7B2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);

    final start = project(flat.first, upOf(0));
    canvas.drawCircle(start, 6, Paint()..color = const Color(0xFF2F7A45));
    canvas.drawCircle(start, 6, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    if (grow >= 1) {
      final end = project(flat.last, upOf(track.length - 1));
      canvas.drawCircle(end, 5, Paint()..color = const Color(0xFFD9BF92));
    }
  }

  @override
  bool shouldRepaint(covariant RouteReliefPainter old) => old.grow != grow || old.yaw != yaw || old.track != track;
}

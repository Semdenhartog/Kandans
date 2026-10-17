import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/geo.dart';

/// Tekent de vorm van een route (zonder kaart) met start- en eindpunt.
class RouteShape extends StatelessWidget {
  const RouteShape({
    super.key,
    required this.polyline,
    this.strokeWidth = 3,
    this.windFromDegrees,
  });

  final String polyline;
  final double strokeWidth;

  /// Als gezet: toon een windpijl (richting waar de wind vandaan komt).
  final double? windFromDegrees;

  @override
  Widget build(BuildContext context) {
    final pts = decodePolyline(polyline);
    return CustomPaint(
      painter: _RoutePainter(pts, strokeWidth, windFromDegrees),
      size: Size.infinite,
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.points, this.strokeWidth, this.windFrom);

  final List<LatLng> points;
  final double strokeWidth;
  final double? windFrom;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = RwColors.surfaceHigh;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      bg,
    );
    if (points.length < 2) return;

    var minLat = points.first.lat, maxLat = points.first.lat;
    var minLon = points.first.lon, maxLon = points.first.lon;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    // Lengtegraden zijn op onze breedte korter: corrigeer voor de verhouding.
    final lonScale = math.cos(((minLat + maxLat) / 2) * math.pi / 180);
    final w = math.max((maxLon - minLon) * lonScale, 1e-9);
    final h = math.max(maxLat - minLat, 1e-9);
    final pad = size.shortestSide * 0.12;
    final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final offsetX = (size.width - w * scale) / 2;
    final offsetY = (size.height - h * scale) / 2;

    Offset map(LatLng p) => Offset(
          offsetX + (p.lon - minLon) * lonScale * scale,
          offsetY + (maxLat - p.lat) * scale,
        );

    final path = Path()..moveTo(map(points.first).dx, map(points.first).dy);
    for (final p in points.skip(1)) {
      final o = map(p);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = RwColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(map(points.first), strokeWidth * 2, Paint()..color = RwColors.text);
    canvas.drawCircle(map(points.last), strokeWidth * 1.5, Paint()..color = RwColors.danger);

    final wf = windFrom;
    if (wf != null) {
      // Pijl in de richting waar de wind naartoe waait.
      final to = (wf + 180) * math.pi / 180;
      final center = Offset(size.width - 28, 28);
      final dir = Offset(math.sin(to), -math.cos(to));
      final start = center - dir * 14;
      final end = center + dir * 14;
      final arrow = Paint()
        ..color = RwColors.muted
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, end, arrow);
      final left = Offset(-dir.dy, dir.dx);
      canvas.drawLine(end, end - dir * 7 + left * 5, arrow);
      canvas.drawLine(end, end - dir * 7 - left * 5, arrow);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.points != points || old.windFrom != windFrom || old.strokeWidth != strokeWidth;
}

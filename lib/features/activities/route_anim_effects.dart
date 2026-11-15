import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/route_anim.dart';
import 'route_anim_data.dart';

/// Tekenhulpjes voor de routevideo: achtergrond, lijn met gloed, komeet en gloeiende kop.
/// Geen blur (te zwaar per beeld): gloed komt van gestapelde doorzichtige lijnen en kleurverloop.
class RouteAnimFx {
  const RouteAnimFx(this.path);

  final RoutePath path;

  Paint stroke(double w, Color col) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = col;

  /// Eigen foto (vullend bijgesneden) met een donkere laag, of effen donker. Eén tekenopdracht per beeld.
  void background(Canvas c, ui.Image? background) {
    const full = Rect.fromLTWH(0, 0, 1080, 1920);
    c.drawRect(full, Paint()..color = raInk);
    final img = background;
    if (img == null) return;
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final s = math.max(full.width / iw, full.height / ih);
    final sw = full.width / s, sh = full.height / s;
    c.drawImageRect(img, Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh), full, Paint()..filterQuality = FilterQuality.medium);
    c.drawRect(
        full,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 1920), [
            raInk.withValues(alpha: 0.62),
            raInk.withValues(alpha: 0.36),
            raInk.withValues(alpha: 0.36),
            raInk.withValues(alpha: 0.78),
          ], const [0, 0.22, 0.6, 1]));
  }

  /// Lijn met gloed: een paar bredere, doorzichtige lagen eronder (geen blur: dat is per beeld veel te zwaar), scherpe kern erbovenop.
  void glowStroke(Canvas c, Path path, Color color, double width, {double strength = 1, double alpha = 1}) {
    if (alpha <= 0) return;
    double a(double v) => (v * strength * alpha).clamp(0.0, 1.0);
    c.drawPath(path, stroke(width * 5.2, raAmber.withValues(alpha: a(0.07))));
    c.drawPath(path, stroke(width * 3.4, raAmber.withValues(alpha: a(0.11))));
    c.drawPath(path, stroke(width * 2.2, raAmber.withValues(alpha: a(0.18))));
    c.drawPath(path, stroke(width, color.withValues(alpha: alpha)));
  }

  /// Lichtkomeet: kop bij [pos] (0..1 van de lijn), staart over [tail] van de lijn, vloeiend uitdovend.
  void comet(Canvas c, double pos, double tail, double width, double alpha) {
    final len = path.length;
    final fade = math.min(1.0, math.min(pos / 0.04, (1 - pos) / 0.04)) * alpha;
    if (fade <= 0) return;
    const bands = 8;
    final head = pos * len;
    final span = tail * len;
    for (var b = 0; b < bands; b++) {
      final a = head - span * (1 - b / bands);
      final z = head - span * (1 - (b + 1) / bands);
      if (z <= 0 || a >= len) continue;
      final f = math.pow((b + 1) / bands, 2.2).toDouble();
      c.drawPath(path.slicePath(a, z + 1), stroke(width * (0.55 + 0.45 * (b + 1) / bands), raHot.withValues(alpha: (0.95 * f * fade).clamp(0.0, 1.0))));
    }
    headGlow(c, path.pointAt(head), 11, alpha: fade);
  }

  /// Gloeiende kop met zachte uitloop via kleurverloop (goedkoop, i.p.v. een grote blur).
  void headGlow(Canvas c, Offset at, double r, {double alpha = 1}) {
    Paint halo(double radius, Color col) => Paint()
      ..shader = ui.Gradient.radial(at, radius, [col, col.withValues(alpha: col.a * 0.35), col.withValues(alpha: 0)], const [0, 0.45, 1]);
    c.drawCircle(at, r * 5, halo(r * 5, raAmber.withValues(alpha: 0.55 * alpha)));
    c.drawCircle(at, r * 2.2, halo(r * 2.2, raHot.withValues(alpha: 0.8 * alpha)));
    c.drawCircle(at, r, Paint()..color = raHot.withValues(alpha: alpha));
  }
}

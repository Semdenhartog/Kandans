import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../domain/route_anim.dart';
import 'route_anim_data.dart';
import 'route_anim_effects.dart';
import 'route_anim_text.dart';

export 'route_anim_data.dart';

/// Tekent één beeld van de routevideo op tijdstip [t] (seconden). Zelfde tekening voor voorbeeld en export.
///
/// In het voorbeeld loopt de tijd via [clock] + [repaint] (één painter, geen nieuwe widgetboom per beeld);
/// bij het maken van de video krijgt elk beeld zijn eigen [t].
class RouteAnimPainter extends CustomPainter {
  RouteAnimPainter({required this.style, required this.data, double t = 0, this.clock, this.highlight, Listenable? repaint})
      : _t = t,
        super(repaint: repaint);

  final RouteAnimStyle style;
  final RouteAnimData data;
  final double Function()? clock;

  /// Onderdeel dat nu versleept wordt (alleen in het voorbeeld getekend, niet in de video).
  final RouteAnimPart? highlight;
  double _t;
  late final RouteAnimFx _fx = RouteAnimFx(data.path);
  late final RouteAnimText _tx = RouteAnimText(photo: data.background != null);
  double get t => _t;

  static const routeBox = Rect.fromLTWH(80, 520, 920, 700);

  /// Standaardplek (ontwerpmaat) van een onderdeel; gebruikt om te slepen en binnen beeld te houden.
  static Rect baseRect(RouteAnimStyle style, RouteAnimPart p) => switch (p) {
        RouteAnimPart.label => const Rect.fromLTWH(90, 190, 900, 56),
        RouteAnimPart.stats => style == RouteAnimStyle.pace ? const Rect.fromLTWH(90, 1390, 900, 230) : const Rect.fromLTWH(90, 1390, 900, 180),
        RouteAnimPart.brand => const Rect.fromLTWH(90, 1680, 520, 92),
      };

  @override
  void paint(Canvas canvas, Size size) {
    final c0 = clock;
    if (c0 != null) _t = c0();
    final k = size.width / routeAnimDesign.width;
    canvas.save();
    canvas.scale(k);
    _fx.background(canvas, data.background, zoom: data.photoZoom, pan: data.photoPan);
    final e = routeProgress(style, t);
    switch (style) {
      case RouteAnimStyle.draw:
        _drawStyle(canvas, e);
      case RouteAnimStyle.comet:
        _cometStyle(canvas);
      case RouteAnimStyle.km:
        _kmStyle(canvas, e);
      case RouteAnimStyle.pace:
        _paceStyle(canvas, e);
      case RouteAnimStyle.echo:
        _echoStyle(canvas);
    }
    _at(canvas, data.layout.label, () => _label(canvas));
    _at(canvas, data.layout.stats, () => style == RouteAnimStyle.pace ? _legend(canvas) : _stats(canvas, e));
    _at(canvas, data.layout.brand, () => _brand(canvas));
    final hl = highlight;
    if (hl != null) {
      final r = baseRect(style, hl).shift(data.layout.of(hl)).inflate(14);
      if (data.layout.of(hl).dx == 0) {
        // Hulplijn: het onderdeel zit op de standaard-marge.
        canvas.drawLine(const Offset(90, 120), const Offset(90, 1800), Paint()
          ..strokeWidth = 2
          ..color = raGold.withValues(alpha: 0.5));
      }
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = raGold.withValues(alpha: 0.9));
    }
    // Zacht in beeld; de losse stijlen (niet-lussen) ook zacht uit.
    var cover = 1 - smoothstep(t / 0.3);
    if (style != RouteAnimStyle.comet && style != RouteAnimStyle.echo) {
      cover = math.max(cover, smoothstep((t - (style.seconds - 0.3)) / 0.3));
    }
    if (cover > 0.001) {
      canvas.drawRect(Offset.zero & routeAnimDesign, Paint()..color = raInk.withValues(alpha: cover));
    }
    canvas.restore();
  }

  // ---------- stijlen ----------
  RoutePath get _p => data.path;

  void _drawStyle(Canvas c, double e) {
    final len = _p.length;
    _ghost(c);
    final settle = smoothstep((t - 5.3) / 0.8);
    final dist = e * len;
    if (dist > 2) {
      _fx.glowStroke(c, _p.slicePath(0, dist), raGold, 10, strength: 1 + 0.5 * smoothstep(1 - (t - 5.0).abs() / 0.5), alpha: 1 - 0.45 * settle);
    }
    if (t > 0.1) {
      c.drawCircle(_p.points.first, 16, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = raGold);
    }
    // Kop met vonken tijdens het tekenen.
    if (t > 0.1 && t < 5.1) {
      final head = _p.pointAt(dist);
      _fx.headGlow(c, head, 17);
      for (var i = 0; i < 12; i++) {
        final back = _p.pointAt(dist - (i + 1) * 16);
        final wob = Offset(math.sin(i * 12.9898 + t * 9) * 12, math.cos(i * 78.233 + t * 7) * 12 - i);
        c.drawCircle(back + wob, 2.2 - i * 0.12, Paint()..color = raHot.withValues(alpha: (1 - i / 12) * 0.85));
      }
    }
    // Finish: schokgolf op de eindplek, daarna lopen er kometen over de lijn.
    final f = t - 5.0;
    if (f > 0 && f < 1.1) {
      c.drawCircle(_p.points.last, 12 + f * 300, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = raHot.withValues(alpha: math.pow(1 - f / 1.1, 1.5).toDouble()));
    }
    final orbit = smoothstep((t - 5.4) / 0.6);
    if (orbit > 0) {
      for (final off in const [0.0, 0.5]) {
        _fx.comet(c, ((t - 5.0) * 0.22 + off) % 1.0, 0.2, 9, orbit);
      }
    }
  }

  void _cometStyle(Canvas c) {
    final breathe = 0.5 + 0.5 * math.sin(2 * math.pi * t / 6);
    _fx.glowStroke(c, _p.fullPath, raGold, 8, strength: 0.9, alpha: 0.42 + 0.14 * breathe);
    final ph = t / 6;
    _fx.comet(c, ph % 1.0, 0.2, 10, 1);
    _fx.comet(c, (ph + 0.5) % 1.0, 0.2, 10, 1);
    _fx.comet(c, (ph * 2 + 0.25) % 1.0, 0.1, 9, 0.8);
  }

  void _kmStyle(Canvas c, double e) {
    final len = _p.length;
    _ghost(c);
    final dist = e * len;
    if (dist > 2) _fx.glowStroke(c, _p.slicePath(0, dist), raGold, 8);
    if (t > 0.1 && t < 5.6) _fx.headGlow(c, _p.pointAt(dist), 14);
    final kms = (data.meters / 1000).floor();
    for (var n = 1; n <= kms; n++) {
      final frac = (n * 1000 - data.trimStartMeters) / math.max(data.pathMeters, 1);
      if (frac < 0 || frac > 1) continue;
      final age = t - (0.5 + 5.0 * frac);
      if (age < 0) continue;
      final s = age < 0.12 ? ui.lerpDouble(0.2, 1.6, age / 0.12)! : (age < 0.3 ? ui.lerpDouble(1.6, 1, (age - 0.12) / 0.18)! : 1.0);
      final at = _p.pointAt(frac * len);
      final r = Rect.fromCenter(center: at, width: 30 * s, height: 30 * s);
      c.drawRect(r.inflate(16), Paint()..color = raAmber.withValues(alpha: 0.14));
      c.drawRect(r.inflate(8), Paint()..color = raAmber.withValues(alpha: 0.28));
      c.drawRect(r, Paint()..color = raGold);
      _tx.draw(c, '$n', Offset(at.dx, at.dy - 62), _tx.mono(24, color: raCream), center: true);
    }
  }

  void _paceStyle(Canvas c, double e) {
    final len = _p.length;
    _ghost(c);
    final spans = data.spans.isNotEmpty ? data.spans : _fallbackSpans();
    final dist = e * len;
    if (dist > 2) {
      final lit = _p.slicePath(0, dist);
      c.drawPath(lit, _fx.stroke(40, raAmber.withValues(alpha: 0.10)));
      c.drawPath(lit, _fx.stroke(26, raAmber.withValues(alpha: 0.18)));
    }
    final pulse = 1 + 0.25 * smoothstep(1 - (t - 6.2).abs() / 1.2);
    for (final s in spans) {
      final a = s.from * len, b = math.min(s.to, e) * len + 1.5;
      if (b <= a + 0.5 || s.from >= e) continue;
      final col = Color.lerp(s.color, Colors.white, (pulse - 1).clamp(0.0, 0.25))!;
      c.drawPath(_p.slicePath(a, b), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.butt
        ..strokeJoin = StrokeJoin.round
        ..color = col);
    }
    if (t > 0.1 && t < 5.1) _fx.headGlow(c, _p.pointAt(dist), 14);
  }

  void _echoStyle(Canvas c) {
    for (var i = 0; i < 3; i++) {
      final u = (t / 3.6 + i / 3) % 1.0;
      final w = 10 + 100 * math.pow(u, 0.6).toDouble();
      c.drawPath(_p.fullPath, _fx.stroke(w, raGold.withValues(alpha: 0.85 * math.pow(1 - u, 1.7).toDouble())));
    }
    final shine = 0.5 + 0.5 * math.sin(2 * math.pi * t / 3.6);
    final core = Color.lerp(const Color(0xFFF0DDB6), Colors.white, shine * 0.8)!;
    c.save();
    c.translate(0, 5);
    c.drawPath(_p.fullPath, _fx.stroke(20, Colors.black.withValues(alpha: 0.18)));
    c.drawPath(_p.fullPath, _fx.stroke(15, Colors.black.withValues(alpha: 0.28)));
    c.restore();
    c.drawPath(_p.fullPath, _fx.stroke(14, core));
  }

  // ---------- onderdelen ----------
  void _ghost(Canvas c) {
    final a = 0.16 * smoothstep(t / 0.7);
    c.drawPath(_p.fullPath, _fx.stroke(4, raCream.withValues(alpha: a)));
  }

  void _at(Canvas c, Offset shift, VoidCallback draw) {
    if (shift == Offset.zero) {
      draw();
      return;
    }
    c.save();
    c.translate(shift.dx, shift.dy);
    draw();
    c.restore();
  }

  List<PaceSpan> _fallbackSpans() {
    const cols = [Color(0xFF8FA3B0), Color(0xFFA9B3B5), Color(0xFFC6C3B8), Color(0xFFE0D2B4), Color(0xFFEFD9A6), Color(0xFFF3D08C), Color(0xFFF0B968), Color(0xFFE8A04A)];
    return [for (var i = 0; i < cols.length; i++) (from: i / cols.length, to: (i + 1) / cols.length + 0.004, color: cols[i])];
  }

  void _label(Canvas c) {
    final a = smoothstep((t - 0.15) / 0.5);
    var s = data.label.toUpperCase();
    if (s.length > 26) s = '${s.substring(0, 25)}…';
    if (style == RouteAnimStyle.pace) s = '$s   ${formatAnimKm(data.meters)}   ${formatAnimTime(data.seconds)}';
    _tx.draw(c, s, const Offset(90, 200), _tx.mono(28, color: raGold), alpha: a);
  }

  void _stats(Canvas c, double e) {
    final live = style == RouteAnimStyle.draw || style == RouteAnimStyle.km;
    final f = live ? e : 1.0;
    final a = live ? smoothstep((t - 0.5) / 0.5) : 1.0;
    _tx.draw(c, tr('AFSTAND'), const Offset(90, 1400), _tx.mono(24), alpha: a);
    _tx.draw(c, formatAnimKm(data.meters * f), const Offset(90, 1440), _tx.num(112), alpha: a);
    _tx.draw(c, tr('TIJD'), const Offset(570, 1400), _tx.mono(24), alpha: a);
    _tx.draw(c, formatAnimTime(data.seconds * f), const Offset(570, 1440), _tx.num(112), alpha: a);
  }

  void _legend(Canvas c) {
    final a = smoothstep((t - 0.5) / 0.5);
    _tx.draw(c, tr('TEMPO PER STUK'), const Offset(90, 1400), _tx.mono(24), alpha: a);
    const n = 8;
    for (var i = 0; i < n; i++) {
      final col = routeAnimPaceColor(i / (n - 1));
      c.drawRect(Rect.fromLTWH(90 + i * 114.0, 1446, 108, 28), Paint()..color = col.withValues(alpha: a));
    }
    if (data.slowPace != null && data.fastPace != null) {
      _tx.draw(c, formatAnimTime(data.slowPace!), const Offset(90, 1500), _tx.num(72), alpha: a);
      _tx.draw(c, formatAnimTime(data.fastPace!), const Offset(990, 1500), _tx.num(72, color: raAmber), alpha: a, right: true);
      _tx.draw(c, tr('LANGZAAM /KM'), const Offset(90, 1590), _tx.mono(24), alpha: a);
      _tx.draw(c, tr('SNEL /KM'), const Offset(990, 1590), _tx.mono(24), alpha: a, right: true);
    }
  }

  void _brand(Canvas c) {
    var x = 90.0;
    final logo = data.logo;
    if (logo != null) {
      const h = 72.0;
      final w = logo.width * h / logo.height;
      c.drawImageRect(logo, Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()), Rect.fromLTWH(x, 1690, w, h),
          Paint()..filterQuality = FilterQuality.high);
      x += w + 24;
    }
    _tx.draw(c, 'KADANS', Offset(x, 1712),
        TextStyle(fontFamily: 'Saira', fontWeight: FontWeight.w800, fontSize: 34, letterSpacing: 8, color: raCream, height: 1, shadows: _tx.photo ? RouteAnimText.shade : null));
  }

  @override
  bool shouldRepaint(covariant RouteAnimPainter old) => old.t != t || old.style != style || old.data != data || old.highlight != highlight;
}

/// Tekent één beeld naar ruwe RGBA-bytes (voor de video-encoder).
Future<Uint8List> renderRouteAnimFrame(RouteAnimPainter painter, int width, int height) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  painter.paint(canvas, Size(width.toDouble(), height.toDouble()));
  final pic = rec.endRecording();
  final img = await pic.toImage(width, height);
  pic.dispose();
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  return bd!.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
}

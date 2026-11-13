import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../domain/route_anim.dart';
import 'splits_card.dart' show runFastColor, runSlowColor;

const _ink = Color(0xFF1A1410);
const _cream = Color(0xFFF1E9DC);
const _gold = Color(0xFFD9BF92);
const _hot = Color(0xFFFFF3D6);
const _amber = Color(0xFFE4A046);
const _mute = Color(0xFFA39280);

/// Kleur van een stuk op tempo: [x] 0 = langzaamst, 1 = snelst (blauw, goud, rood). Gelijk in de lijn en de legenda.
Color routeAnimPaceColor(double x) =>
    x < 0.5 ? Color.lerp(runSlowColor, _gold, x * 2)! : Color.lerp(_gold, runFastColor, (x - 0.5) * 2)!;

/// Vaste ontwerpmaat van de video; alles wordt hierin getekend en daarna geschaald naar het beeld.
const routeAnimDesign = Size(1080, 1920);

/// Wat de video laat zien.
class RouteAnimData {
  const RouteAnimData({
    required this.path,
    required this.label,
    required this.meters,
    required this.seconds,
    required this.pathMeters,
    this.trimStartMeters = 0,
    this.spans = const [],
    this.slowPace,
    this.fastPace,
    this.logo,
  });

  final RoutePath path;
  final String label;

  /// Hele run (voor de cijfers) en de getoonde lijn (zonder privacyzone), in meters en seconden.
  final double meters;
  final double seconds;
  final double pathMeters;

  /// Meters van de run die niet getoond worden aan het begin (privacyzone), voor de kilometerstippen.
  final double trimStartMeters;

  /// Tempo-stukken over de lijn (leeg = standaardkleuren) en traagste/snelste tempo in s/km.
  final List<PaceSpan> spans;
  final double? slowPace;
  final double? fastPace;
  final ui.Image? logo;
}

/// Tekent één beeld van de routevideo op tijdstip [t] (seconden). Zelfde tekening voor voorbeeld en export.
class RouteAnimPainter extends CustomPainter {
  RouteAnimPainter({required this.style, required this.data, required this.t});

  final RouteAnimStyle style;
  final RouteAnimData data;
  final double t;

  static const routeBox = Rect.fromLTWH(80, 520, 920, 700);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / routeAnimDesign.width;
    canvas.save();
    canvas.scale(k);
    canvas.drawRect(Offset.zero & routeAnimDesign, Paint()..color = _ink);
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
    _label(canvas);
    if (style == RouteAnimStyle.pace) {
      _legend(canvas);
    } else {
      _stats(canvas, e);
    }
    _brand(canvas);
    // Zacht in beeld; de losse stijlen (niet-lussen) ook zacht uit.
    var cover = 1 - smoothstep(t / 0.3);
    if (style != RouteAnimStyle.comet && style != RouteAnimStyle.echo) {
      cover = math.max(cover, smoothstep((t - (style.seconds - 0.3)) / 0.3));
    }
    if (cover > 0.001) {
      canvas.drawRect(Offset.zero & routeAnimDesign, Paint()..color = _ink.withValues(alpha: cover));
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
      _glowStroke(c, _p.slice(0, dist), _gold, 10, strength: 1 + 0.5 * smoothstep(1 - (t - 5.0).abs() / 0.5), alpha: 1 - 0.45 * settle);
    }
    if (t > 0.1) {
      c.drawCircle(_p.points.first, 16, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _gold);
    }
    // Kop met vonken tijdens het tekenen.
    if (t > 0.1 && t < 5.1) {
      final head = _p.pointAt(dist);
      _headGlow(c, head, 17);
      for (var i = 0; i < 12; i++) {
        final back = _p.pointAt(dist - (i + 1) * 16);
        final wob = Offset(math.sin(i * 12.9898 + t * 9) * 12, math.cos(i * 78.233 + t * 7) * 12 - i);
        c.drawCircle(back + wob, 2.2 - i * 0.12, Paint()..color = _hot.withValues(alpha: (1 - i / 12) * 0.85));
      }
    }
    // Finish: schokgolf op de eindplek, daarna lopen er kometen over de lijn.
    final f = t - 5.0;
    if (f > 0 && f < 1.1) {
      c.drawCircle(_p.points.last, 12 + f * 300, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = _hot.withValues(alpha: math.pow(1 - f / 1.1, 1.5).toDouble()));
    }
    final orbit = smoothstep((t - 5.4) / 0.6);
    if (orbit > 0) {
      for (final off in const [0.0, 0.5]) {
        _comet(c, ((t - 5.0) * 0.22 + off) % 1.0, 0.2, 9, orbit);
      }
    }
  }

  void _cometStyle(Canvas c) {
    final breathe = 0.5 + 0.5 * math.sin(2 * math.pi * t / 6);
    _glowStroke(c, _p.points, _gold, 8, strength: 0.9, alpha: 0.42 + 0.14 * breathe);
    final ph = t / 6;
    _comet(c, ph % 1.0, 0.2, 10, 1);
    _comet(c, (ph + 0.5) % 1.0, 0.2, 10, 1);
    _comet(c, (ph * 2 + 0.25) % 1.0, 0.1, 9, 0.8);
  }

  void _kmStyle(Canvas c, double e) {
    final len = _p.length;
    _ghost(c);
    final dist = e * len;
    if (dist > 2) _glowStroke(c, _p.slice(0, dist), _gold, 8);
    if (t > 0.1 && t < 5.6) _headGlow(c, _p.pointAt(dist), 14);
    final kms = (data.meters / 1000).floor();
    for (var n = 1; n <= kms; n++) {
      final frac = (n * 1000 - data.trimStartMeters) / math.max(data.pathMeters, 1);
      if (frac < 0 || frac > 1) continue;
      final age = t - (0.5 + 5.0 * frac);
      if (age < 0) continue;
      final s = age < 0.12 ? ui.lerpDouble(0.2, 1.6, age / 0.12)! : (age < 0.3 ? ui.lerpDouble(1.6, 1, (age - 0.12) / 0.18)! : 1.0);
      final at = _p.pointAt(frac * len);
      final r = Rect.fromCenter(center: at, width: 30 * s, height: 30 * s);
      c.drawRect(r.inflate(10), Paint()
        ..color = _amber.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
      c.drawRect(r, Paint()..color = _gold);
      _text(c, '$n', Offset(at.dx, at.dy - 62), _mono(24, color: _cream), center: true);
    }
  }

  void _paceStyle(Canvas c, double e) {
    final len = _p.length;
    _ghost(c);
    final spans = data.spans.isNotEmpty ? data.spans : _fallbackSpans();
    final dist = e * len;
    if (dist > 2) {
      c.drawPath(_pathOf(_p.slice(0, dist)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _amber.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16));
    }
    final pulse = 1 + 0.25 * smoothstep(1 - (t - 6.2).abs() / 1.2);
    for (final s in spans) {
      final a = s.from * len, b = math.min(s.to, e) * len + 1.5;
      if (b <= a + 0.5 || s.from >= e) continue;
      final col = Color.lerp(s.color, Colors.white, (pulse - 1).clamp(0.0, 0.25))!;
      c.drawPath(_pathOf(_p.slice(a, b)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.butt
        ..strokeJoin = StrokeJoin.round
        ..color = col);
    }
    if (t > 0.1 && t < 5.1) _headGlow(c, _p.pointAt(dist), 14);
  }

  void _echoStyle(Canvas c) {
    for (var i = 0; i < 3; i++) {
      final u = (t / 3.6 + i / 3) % 1.0;
      final w = 10 + 100 * math.pow(u, 0.6).toDouble();
      c.drawPath(_pathOf(_p.points), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _gold.withValues(alpha: 0.85 * math.pow(1 - u, 1.7).toDouble()));
    }
    final shine = 0.5 + 0.5 * math.sin(2 * math.pi * t / 3.6);
    final core = Color.lerp(const Color(0xFFF0DDB6), Colors.white, shine * 0.8)!;
    c.drawPath(_pathOf(_p.points.map((o) => o.translate(0, 4)).toList()), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.black.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    c.drawPath(_pathOf(_p.points), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = core);
  }

  // ---------- onderdelen ----------
  void _ghost(Canvas c) {
    final a = 0.16 * smoothstep(t / 0.7);
    c.drawPath(_pathOf(_p.points), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _cream.withValues(alpha: a));
  }

  Path _pathOf(List<Offset> pts) {
    final p = Path();
    if (pts.isEmpty) return p;
    p.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    return p;
  }

  /// Lijn met gloed: brede zachte lagen eronder, scherpe kern erbovenop.
  void _glowStroke(Canvas c, List<Offset> pts, Color color, double width, {double strength = 1, double alpha = 1}) {
    if (pts.length < 2 || alpha <= 0) return;
    final path = _pathOf(pts);
    Paint layer(double w, double sigma, Color col) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = col
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    c.drawPath(path, layer(width * 4.5, 26, _amber.withValues(alpha: (0.30 * strength * alpha).clamp(0.0, 1.0))));
    c.drawPath(path, layer(width * 2.2, 10, _amber.withValues(alpha: (0.45 * strength * alpha).clamp(0.0, 1.0))));
    c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color.withValues(alpha: alpha));
  }

  /// Lichtkomeet: kop bij [pos] (0..1 van de lijn), staart over [tail] van de lijn, vloeiend uitdovend.
  void _comet(Canvas c, double pos, double tail, double width, double alpha) {
    final len = _p.length;
    final fade = math.min(1.0, math.min(pos / 0.04, (1 - pos) / 0.04)) * alpha;
    if (fade <= 0) return;
    const bands = 8;
    final head = pos * len;
    final span = tail * len;
    for (var b = 0; b < bands; b++) {
      final a = head - span * (1 - b / bands);
      final z = head - span * (1 - (b + 1) / bands);
      final pts = _p.slice(a, z + 1);
      if (pts.length < 2) continue;
      final f = math.pow((b + 1) / bands, 2.2).toDouble();
      c.drawPath(_pathOf(pts), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * (0.55 + 0.45 * (b + 1) / bands)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _hot.withValues(alpha: (0.95 * f * fade).clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    }
    _headGlow(c, _p.pointAt(head), 11, alpha: fade);
  }

  void _headGlow(Canvas c, Offset at, double r, {double alpha = 1}) {
    c.drawCircle(at, r * 4.5, Paint()
      ..color = _amber.withValues(alpha: 0.5 * alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34));
    c.drawCircle(at, r * 1.7, Paint()
      ..color = _hot.withValues(alpha: 0.75 * alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    c.drawCircle(at, r, Paint()..color = _hot.withValues(alpha: alpha));
  }

  List<PaceSpan> _fallbackSpans() {
    const cols = [Color(0xFF8FA3B0), Color(0xFFA9B3B5), Color(0xFFC6C3B8), Color(0xFFE0D2B4), Color(0xFFEFD9A6), Color(0xFFF3D08C), Color(0xFFF0B968), Color(0xFFE8A04A)];
    return [for (var i = 0; i < cols.length; i++) (from: i / cols.length, to: (i + 1) / cols.length + 0.004, color: cols[i])];
  }

  // ---------- tekst ----------
  TextStyle _mono(double size, {Color color = _mute}) => TextStyle(fontFamily: 'KadansMono', fontSize: size, letterSpacing: 3, color: color, height: 1);

  TextStyle _num(double size, {Color color = _cream}) => TextStyle(
        fontFamily: 'Saira',
        fontWeight: FontWeight.w800,
        fontSize: size,
        color: color,
        height: 1,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  void _text(Canvas c, String s, Offset at, TextStyle style, {bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, center ? Offset(at.dx - tp.width / 2, at.dy) : at);
  }

  void _label(Canvas c) {
    final a = smoothstep((t - 0.15) / 0.5);
    var s = data.label.toUpperCase();
    if (s.length > 26) s = '${s.substring(0, 25)}…';
    if (style == RouteAnimStyle.pace) s = '$s   ${formatAnimKm(data.meters)}   ${formatAnimTime(data.seconds)}';
    c.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: a));
    _text(c, s, const Offset(90, 200), _mono(28, color: _gold));
    c.restore();
  }

  void _stats(Canvas c, double e) {
    final live = style == RouteAnimStyle.draw || style == RouteAnimStyle.km;
    final f = live ? e : 1.0;
    final a = live ? smoothstep((t - 0.5) / 0.5) : 1.0;
    c.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: a));
    _text(c, tr('AFSTAND'), const Offset(90, 1400), _mono(24));
    _text(c, formatAnimKm(data.meters * f), const Offset(90, 1440), _num(112));
    _text(c, tr('TIJD'), const Offset(570, 1400), _mono(24));
    _text(c, formatAnimTime(data.seconds * f), const Offset(570, 1440), _num(112));
    c.restore();
  }

  void _legend(Canvas c) {
    final a = smoothstep((t - 0.5) / 0.5);
    c.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: a));
    _text(c, tr('TEMPO PER STUK'), const Offset(90, 1400), _mono(24));
    const n = 8;
    for (var i = 0; i < n; i++) {
      final x = i / (n - 1);
      final col = routeAnimPaceColor(x);
      c.drawRect(Rect.fromLTWH(90 + i * 114.0, 1446, 108, 28), Paint()..color = col);
    }
    if (data.slowPace != null && data.fastPace != null) {
      _text(c, formatAnimTime(data.slowPace!), const Offset(90, 1500), _num(72));
      final fast = TextPainter(text: TextSpan(text: formatAnimTime(data.fastPace!), style: _num(72, color: _amber)), textDirection: TextDirection.ltr)..layout();
      fast.paint(c, Offset(990 - fast.width, 1500));
      _text(c, tr('LANGZAAM /KM'), const Offset(90, 1590), _mono(24));
      final sn = TextPainter(text: TextSpan(text: tr('SNEL /KM'), style: _mono(24)), textDirection: TextDirection.ltr)..layout();
      sn.paint(c, Offset(990 - sn.width, 1590));
    }
    c.restore();
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
    _text(c, 'KADANS', Offset(x, 1712), TextStyle(fontFamily: 'Saira', fontWeight: FontWeight.w800, fontSize: 34, letterSpacing: 8, color: _cream, height: 1));
  }

  @override
  bool shouldRepaint(covariant RouteAnimPainter old) => old.t != t || old.style != style || old.data != data;
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

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
    this.background,
    this.layout = RouteAnimLayout.none,
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

  /// Eigen foto achter de lijn (met donkere laag erover voor de leesbaarheid); null = effen donker.
  final ui.Image? background;

  /// Verschuiving van label, cijfers en logo.
  final RouteAnimLayout layout;

  RouteAnimData copyWith({RouteAnimLayout? layout}) => RouteAnimData(
        path: path,
        label: label,
        meters: meters,
        seconds: seconds,
        pathMeters: pathMeters,
        trimStartMeters: trimStartMeters,
        spans: spans,
        slowPace: slowPace,
        fastPace: fastPace,
        logo: logo,
        background: background,
        layout: layout ?? this.layout,
      );
}

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
    _background(canvas);
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
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = _gold.withValues(alpha: 0.9));
    }
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
      _glowStroke(c, _p.slicePath(0, dist), _gold, 10, strength: 1 + 0.5 * smoothstep(1 - (t - 5.0).abs() / 0.5), alpha: 1 - 0.45 * settle);
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
    _glowStroke(c, _p.fullPath, _gold, 8, strength: 0.9, alpha: 0.42 + 0.14 * breathe);
    final ph = t / 6;
    _comet(c, ph % 1.0, 0.2, 10, 1);
    _comet(c, (ph + 0.5) % 1.0, 0.2, 10, 1);
    _comet(c, (ph * 2 + 0.25) % 1.0, 0.1, 9, 0.8);
  }

  void _kmStyle(Canvas c, double e) {
    final len = _p.length;
    _ghost(c);
    final dist = e * len;
    if (dist > 2) _glowStroke(c, _p.slicePath(0, dist), _gold, 8);
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
      c.drawRect(r.inflate(16), Paint()..color = _amber.withValues(alpha: 0.14));
      c.drawRect(r.inflate(8), Paint()..color = _amber.withValues(alpha: 0.28));
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
      final lit = _p.slicePath(0, dist);
      c.drawPath(lit, _stroke(40, _amber.withValues(alpha: 0.10)));
      c.drawPath(lit, _stroke(26, _amber.withValues(alpha: 0.18)));
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
    if (t > 0.1 && t < 5.1) _headGlow(c, _p.pointAt(dist), 14);
  }

  void _echoStyle(Canvas c) {
    for (var i = 0; i < 3; i++) {
      final u = (t / 3.6 + i / 3) % 1.0;
      final w = 10 + 100 * math.pow(u, 0.6).toDouble();
      c.drawPath(_p.fullPath, _stroke(w, _gold.withValues(alpha: 0.85 * math.pow(1 - u, 1.7).toDouble())));
    }
    final shine = 0.5 + 0.5 * math.sin(2 * math.pi * t / 3.6);
    final core = Color.lerp(const Color(0xFFF0DDB6), Colors.white, shine * 0.8)!;
    c.save();
    c.translate(0, 5);
    c.drawPath(_p.fullPath, _stroke(20, Colors.black.withValues(alpha: 0.18)));
    c.drawPath(_p.fullPath, _stroke(15, Colors.black.withValues(alpha: 0.28)));
    c.restore();
    c.drawPath(_p.fullPath, _stroke(14, core));
  }

  // ---------- onderdelen ----------
  void _ghost(Canvas c) {
    final a = 0.16 * smoothstep(t / 0.7);
    c.drawPath(_p.fullPath, _stroke(4, _cream.withValues(alpha: a)));
  }

  Paint _stroke(double w, Color col) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = col;

  /// Eigen foto (vullend bijgesneden) met een donkere laag, of effen donker. Eén tekenopdracht per beeld.
  void _background(Canvas c) {
    const full = Rect.fromLTWH(0, 0, 1080, 1920);
    c.drawRect(full, Paint()..color = _ink);
    final img = data.background;
    if (img == null) return;
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final s = math.max(full.width / iw, full.height / ih);
    final sw = full.width / s, sh = full.height / s;
    c.drawImageRect(img, Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh), full, Paint()..filterQuality = FilterQuality.medium);
    c.drawRect(
        full,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 1920), [
            _ink.withValues(alpha: 0.62),
            _ink.withValues(alpha: 0.36),
            _ink.withValues(alpha: 0.36),
            _ink.withValues(alpha: 0.78),
          ], const [0, 0.22, 0.6, 1]));
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

  /// Lijn met gloed: een paar bredere, doorzichtige lagen eronder (geen blur: dat is per beeld veel te zwaar), scherpe kern erbovenop.
  void _glowStroke(Canvas c, Path path, Color color, double width, {double strength = 1, double alpha = 1}) {
    if (alpha <= 0) return;
    double a(double v) => (v * strength * alpha).clamp(0.0, 1.0);
    c.drawPath(path, _stroke(width * 5.2, _amber.withValues(alpha: a(0.07))));
    c.drawPath(path, _stroke(width * 3.4, _amber.withValues(alpha: a(0.11))));
    c.drawPath(path, _stroke(width * 2.2, _amber.withValues(alpha: a(0.18))));
    c.drawPath(path, _stroke(width, color.withValues(alpha: alpha)));
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
      if (z <= 0 || a >= len) continue;
      final f = math.pow((b + 1) / bands, 2.2).toDouble();
      c.drawPath(_p.slicePath(a, z + 1), _stroke(width * (0.55 + 0.45 * (b + 1) / bands), _hot.withValues(alpha: (0.95 * f * fade).clamp(0.0, 1.0))));
    }
    _headGlow(c, _p.pointAt(head), 11, alpha: fade);
  }

  /// Gloeiende kop met zachte uitloop via kleurverloop (goedkoop, i.p.v. een grote blur).
  void _headGlow(Canvas c, Offset at, double r, {double alpha = 1}) {
    Paint halo(double radius, Color col) => Paint()
      ..shader = ui.Gradient.radial(at, radius, [col, col.withValues(alpha: col.a * 0.35), col.withValues(alpha: 0)], const [0, 0.45, 1]);
    c.drawCircle(at, r * 5, halo(r * 5, _amber.withValues(alpha: 0.55 * alpha)));
    c.drawCircle(at, r * 2.2, halo(r * 2.2, _hot.withValues(alpha: 0.8 * alpha)));
    c.drawCircle(at, r, Paint()..color = _hot.withValues(alpha: alpha));
  }

  List<PaceSpan> _fallbackSpans() {
    const cols = [Color(0xFF8FA3B0), Color(0xFFA9B3B5), Color(0xFFC6C3B8), Color(0xFFE0D2B4), Color(0xFFEFD9A6), Color(0xFFF3D08C), Color(0xFFF0B968), Color(0xFFE8A04A)];
    return [for (var i = 0; i < cols.length; i++) (from: i / cols.length, to: (i + 1) / cols.length + 0.004, color: cols[i])];
  }

  // ---------- tekst ----------
  bool get _photo => data.background != null;

  TextStyle _mono(double size, {Color color = _mute}) => TextStyle(
      fontFamily: 'KadansMono', fontSize: size, letterSpacing: 3, color: color, height: 1, shadows: _photo ? _shade : null);

  TextStyle _num(double size, {Color color = _cream}) => TextStyle(
        fontFamily: 'Saira',
        fontWeight: FontWeight.w800,
        fontSize: size,
        color: color,
        height: 1,
        fontFeatures: const [FontFeature.tabularFigures()],
        shadows: _photo ? _shade : null,
      );

  static const _shade = [Shadow(color: Color(0xAA000000), blurRadius: 10, offset: Offset(0, 2))];

  /// Opgemaakte tekst wordt bewaard: opmaken is het duurste deel van tekst tekenen en de zinnen zijn bijna elk beeld gelijk.
  static final Map<String, TextPainter> _cache = {};

  TextPainter _painter(String s, TextStyle st, double alpha) {
    // Doorzichtigheid in 32 stappen, zodat het invagen netjes loopt maar de bewaarplaats klein blijft.
    final q = (alpha.clamp(0.0, 1.0) * 32).round();
    final col = (st.color ?? _cream).withValues(alpha: (st.color?.a ?? 1) * q / 32);
    final key = '${st.fontFamily}|${st.fontSize}|${col.toARGB32()}|${st.shadows != null}|$s';
    var tp = _cache[key];
    if (tp == null) {
      if (_cache.length > 400) _cache.clear();
      final style = st.copyWith(color: col, shadows: st.shadows?.map((x) => Shadow(color: x.color.withValues(alpha: x.color.a * q / 32), blurRadius: x.blurRadius, offset: x.offset)).toList());
      tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
      _cache[key] = tp;
    }
    return tp;
  }

  void _text(Canvas c, String s, Offset at, TextStyle style, {bool center = false, double alpha = 1, bool right = false}) {
    if (alpha <= 0.01) return;
    final tp = _painter(s, style, alpha);
    tp.paint(c, center ? Offset(at.dx - tp.width / 2, at.dy) : (right ? Offset(at.dx - tp.width, at.dy) : at));
  }

  void _label(Canvas c) {
    final a = smoothstep((t - 0.15) / 0.5);
    var s = data.label.toUpperCase();
    if (s.length > 26) s = '${s.substring(0, 25)}…';
    if (style == RouteAnimStyle.pace) s = '$s   ${formatAnimKm(data.meters)}   ${formatAnimTime(data.seconds)}';
    _text(c, s, const Offset(90, 200), _mono(28, color: _gold), alpha: a);
  }

  void _stats(Canvas c, double e) {
    final live = style == RouteAnimStyle.draw || style == RouteAnimStyle.km;
    final f = live ? e : 1.0;
    final a = live ? smoothstep((t - 0.5) / 0.5) : 1.0;
    _text(c, tr('AFSTAND'), const Offset(90, 1400), _mono(24), alpha: a);
    _text(c, formatAnimKm(data.meters * f), const Offset(90, 1440), _num(112), alpha: a);
    _text(c, tr('TIJD'), const Offset(570, 1400), _mono(24), alpha: a);
    _text(c, formatAnimTime(data.seconds * f), const Offset(570, 1440), _num(112), alpha: a);
  }

  void _legend(Canvas c) {
    final a = smoothstep((t - 0.5) / 0.5);
    _text(c, tr('TEMPO PER STUK'), const Offset(90, 1400), _mono(24), alpha: a);
    const n = 8;
    for (var i = 0; i < n; i++) {
      final col = routeAnimPaceColor(i / (n - 1));
      c.drawRect(Rect.fromLTWH(90 + i * 114.0, 1446, 108, 28), Paint()..color = col.withValues(alpha: a));
    }
    if (data.slowPace != null && data.fastPace != null) {
      _text(c, formatAnimTime(data.slowPace!), const Offset(90, 1500), _num(72), alpha: a);
      _text(c, formatAnimTime(data.fastPace!), const Offset(990, 1500), _num(72, color: _amber), alpha: a, right: true);
      _text(c, tr('LANGZAAM /KM'), const Offset(90, 1590), _mono(24), alpha: a);
      _text(c, tr('SNEL /KM'), const Offset(990, 1590), _mono(24), alpha: a, right: true);
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
    _text(c, 'KADANS', Offset(x, 1712),
        TextStyle(fontFamily: 'Saira', fontWeight: FontWeight.w800, fontSize: 34, letterSpacing: 8, color: _cream, height: 1, shadows: _photo ? _shade : null));
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

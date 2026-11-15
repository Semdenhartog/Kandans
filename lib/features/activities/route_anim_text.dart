import 'package:flutter/material.dart';

import 'route_anim_data.dart';

/// Tekst voor de routevideo: opmaak, schaduw (bij een foto erachter) en een bewaarplaats voor opgemaakte tekst.
class RouteAnimText {
  const RouteAnimText({required this.photo});

  final bool photo;


  TextStyle mono(double size, {Color color = raMute}) => TextStyle(
      fontFamily: 'KadansMono', fontSize: size, letterSpacing: 3, color: color, height: 1, shadows: photo ? shade : null);

  TextStyle num(double size, {Color color = raCream}) => TextStyle(
        fontFamily: 'Saira',
        fontWeight: FontWeight.w800,
        fontSize: size,
        color: color,
        height: 1,
        fontFeatures: const [FontFeature.tabularFigures()],
        shadows: photo ? shade : null,
      );

  static const shade = [Shadow(color: Color(0xAA000000), blurRadius: 10, offset: Offset(0, 2))];

  /// Opgemaakte tekst wordt bewaard: opmaken is het duurste deel van tekst tekenen en de zinnen zijn bijna elk beeld gelijk.
  static final Map<String, TextPainter> _cache = {};

  TextPainter _painter(String s, TextStyle st, double alpha) {
    // Doorzichtigheid in 32 stappen, zodat het invagen netjes loopt maar de bewaarplaats klein blijft.
    final q = (alpha.clamp(0.0, 1.0) * 32).round();
    final col = (st.color ?? raCream).withValues(alpha: (st.color?.a ?? 1) * q / 32);
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

  void draw(Canvas c, String s, Offset at, TextStyle style, {bool center = false, double alpha = 1, bool right = false}) {
    if (alpha <= 0.01) return;
    final tp = _painter(s, style, alpha);
    tp.paint(c, center ? Offset(at.dx - tp.width / 2, at.dy) : (right ? Offset(at.dx - tp.width, at.dy) : at));
  }
}

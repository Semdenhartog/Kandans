import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Lidmaatschapskaart in de vorm van een creditcard: geborsteld zwart (of goud voor Premium),
/// een getekende hoogtelijn, je naam in reliëf, je totalen en "loper sinds".
/// Kantelt licht mee als je hem aanraakt.
class MemberCard extends StatefulWidget {
  const MemberCard({
    super.key,
    required this.name,
    required this.email,
    required this.runs,
    required this.km,
    required this.badges,
    required this.since,
    required this.premium,
    this.onBadges,
  });
  final String name;
  final String email;
  final int runs;
  final double km;
  final int badges;
  final DateTime? since;
  final bool premium;
  final VoidCallback? onBadges;

  @override
  State<MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<MemberCard> {
  Offset _tilt = Offset.zero;

  void _move(Offset local, Size size) {
    final dx = (local.dx / size.width - 0.5).clamp(-0.5, 0.5);
    final dy = (local.dy / size.height - 0.5).clamp(-0.5, 0.5);
    setState(() => _tilt = Offset(dx, dy));
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final gold = w.premium;
    const months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
    final since = w.since == null ? '—' : '${months[w.since!.month - 1]} ${w.since!.year}';
    final ink = gold ? const Color(0xFF2A1E05) : rwZandAvond.text;
    final soft = gold ? const Color(0xAA2A1E05) : rwZandAvond.subtle;

    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      final height = width / 1.586; // echte creditcardverhouding
      final size = Size(width, height);
      // Listener i.p.v. GestureDetector: kantelen mag het scrollen van de lijst nooit blokkeren.
      return Listener(
        onPointerDown: (d) {
          HapticFeedback.selectionClick();
          _move(d.localPosition, size);
        },
        onPointerMove: (d) => _move(d.localPosition, size),
        onPointerUp: (_) => setState(() => _tilt = Offset.zero),
        onPointerCancel: (_) => setState(() => _tilt = Offset.zero),
        child: TweenAnimationBuilder<Offset>(
          tween: Tween(end: _tilt),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          builder: (context, t, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(-t.dy * 0.22)
              ..rotateY(t.dx * 0.22),
            child: Stack(children: [
              child!,
              // Lichtreflectie die meebeweegt met de kanteling.
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-1 - t.dx * 2, -1 - t.dy * 2),
                          end: Alignment(1 - t.dx * 2, 1 - t.dy * 2),
                          colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: gold ? 0.22 : 0.08), Colors.white.withValues(alpha: 0)],
                          stops: const [0.3, 0.5, 0.7],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: gold
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF6E3A1), Color(0xFFD4AF37), Color(0xFFB08A2E), Color(0xFFE9CF7A)],
                      stops: [0, 0.4, 0.75, 1],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF26262B), Color(0xFF141417), Color(0xFF0C0C0E)],
                    ),
              border: Border.all(color: gold ? const Color(0x66FFFFFF) : const Color(0x1FFFFFFF)),
              boxShadow: [
                BoxShadow(color: (gold ? const Color(0xFFD4AF37) : rwZandAvond.accent).withValues(alpha: 0.10), blurRadius: 40, spreadRadius: -6),
                BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 28, spreadRadius: -8, offset: const Offset(0, 12)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: _CardArt(gold: gold))),
                Padding(
                  padding: EdgeInsets.fromLTRB(width * 0.065, height * 0.09, width * 0.065, height * 0.08),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('KADANS',
                            style: TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, letterSpacing: 3.2, fontSize: 13, color: gold ? ink : rwZandAvond.accent)),
                        const Spacer(),
                        Text(gold ? 'PREMIUM' : 'MEMBER',
                            style: TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w700, letterSpacing: 2.4, fontSize: 11, color: soft)),
                      ]),
                      const SizedBox(height: 14),
                      // "Chip"
                      Container(
                        width: width * 0.11,
                        height: width * 0.085,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: const LinearGradient(colors: [Color(0xFFE8D08A), Color(0xFFB8963E), Color(0xFFE2C676)]),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.25), width: 0.6),
                        ),
                        child: CustomPaint(painter: _ChipLines()),
                      ),
                      const Spacer(),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          w.name.isEmpty ? 'LOPER' : w.name.toUpperCase(),
                          style: TextStyle(
                            fontFamily: RwFonts.display,
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                            letterSpacing: 2.6,
                            color: ink,
                            shadows: [Shadow(color: Colors.black.withValues(alpha: gold ? 0.18 : 0.6), offset: const Offset(0, 1.2), blurRadius: 1)],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _Fig(label: 'KM', value: '${w.km.round()}', ink: ink, soft: soft),
                          SizedBox(width: width * 0.06),
                          _Fig(label: 'RUNS', value: '${w.runs}', ink: ink, soft: soft),
                          SizedBox(width: width * 0.06),
                          GestureDetector(
                            onTap: w.onBadges,
                            child: _Fig(label: 'BADGES', value: '${w.badges}', ink: ink, soft: soft),
                          ),
                          const Spacer(),
                          _Fig(label: 'LOPER SINDS', value: since, ink: ink, soft: soft, end: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

class _Fig extends StatelessWidget {
  const _Fig({required this.label, required this.value, required this.ink, required this.soft, this.end = false});
  final String label, value;
  final Color ink, soft;
  final bool end;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 9, letterSpacing: 1.6, fontWeight: FontWeight.w700, color: soft)),
          Text(value, style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 16, fontWeight: FontWeight.w700, color: ink)),
        ],
      );
}

/// Fijne geborstelde lijnen en een hoogtelijn als "landschap" achter de tekst.
class _CardArt extends CustomPainter {
  _CardArt({required this.gold});
  final bool gold;

  @override
  void paint(Canvas canvas, Size size) {
    final brush = Paint()
      ..color = (gold ? Colors.white : Colors.white).withValues(alpha: gold ? 0.06 : 0.018)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 2), brush);
    }
    // Hoogtelijn
    final p = Path();
    for (var i = 0; i <= 60; i++) {
      final x = i / 60 * size.width;
      final y = size.height * (0.44 + 0.04 * math.sin(i * 0.31) + 0.025 * math.sin(i * 0.9 + 1) - 0.07 * math.exp(-math.pow((i - 38) / 7, 2)));
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = gold ? const Color(0x552A1E05) : rwZandAvond.accent.withValues(alpha: 0.35),
    );
    final fill = Path.from(p)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gold
              ? [const Color(0x222A1E05), const Color(0x002A1E05)]
              : [rwZandAvond.accent.withValues(alpha: 0.10), rwZandAvond.accent.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    // Gloed rechtsboven
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.05),
      size.width * 0.5,
      Paint()
        ..shader = RadialGradient(colors: [
          (gold ? Colors.white : rwZandAvond.accent).withValues(alpha: gold ? 0.25 : 0.10),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: Offset(size.width * 0.92, size.height * 0.05), radius: size.width * 0.5)),
    );
  }

  @override
  bool shouldRepaint(covariant _CardArt old) => old.gold != gold;
}

class _ChipLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), p);
    canvas.drawLine(Offset(size.width * 2 / 3, 0), Offset(size.width * 2 / 3, size.height), p);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), p);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.33, size.height * 0.25, size.width * 0.34, size.height * 0.5), const Radius.circular(2)), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

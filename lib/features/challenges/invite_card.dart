import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/theme.dart';

/// Link waarmee een vriend je toevoegt: opent de app (of de downloadpagina) met je code ingevuld.
String inviteLink(String code) => '${AppConfig.siteUrl}/vriend.html?code=${Uri.encodeQueryComponent(code)}';

/// Haalt een vriendcode uit tekst: een uitnodigingslink (…?code=K7QX2M) of een losse code van 6 tekens.
String? friendCodeFrom(String text) {
  final t = text.trim();
  final link = RegExp(r'[?&]code=([A-Za-z0-9]{4,8})').firstMatch(t);
  if (link != null) return link.group(1)!.toUpperCase();
  final bare = RegExp(r'^[A-Za-z0-9]{6}$').firstMatch(t);
  if (bare != null && RegExp(r'[0-9]').hasMatch(t) && RegExp(r'[A-Za-z]').hasMatch(t)) return t.toUpperCase();
  return null;
}

/// Luxe uitnodigingskaart (staand 1080×1350), altijd donker-goud.
Future<Uint8List> inviteCardPng({required String code, required String name}) async {
  const w = 1080.0, h = 1350.0;
  const pal = rwZandAvond;
  const gold = Color(0xFFD9BF92), goldDeep = Color(0xFFB8955F), goldLight = Color(0xFFF0DDB6);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));

  // Warme, donkere ondergrond met een zachte gloed achter de ringen.
  c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = pal.background);
  c.drawCircle(
    const Offset(w / 2, 430),
    520,
    Paint()
      ..shader = ui.Gradient.radial(const Offset(w / 2, 430), 520, [
        const Color(0xFF3A2F22),
        pal.background,
      ]),
  );

  // Dunne gouden routelijn over de kaart.
  final route = Path()
    ..moveTo(-20, 980)
    ..cubicTo(220, 860, 300, 1120, 540, 1010)
    ..cubicTo(760, 910, 860, 1060, 1100, 930);
  c.drawPath(
    route,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = gold.withValues(alpha: 0.35),
  );

  // Gouden rand.
  final frame = RRect.fromRectAndRadius(const Rect.fromLTWH(36, 36, w - 72, h - 72), const Radius.circular(36));
  c.drawRRect(
    frame,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(w, h), [goldLight, goldDeep, goldLight]),
  );

  // Het merk (gouden ringen).
  try {
    final data = await rootBundle.load('assets/logo/mark.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 520);
    final img = (await codec.getNextFrame()).image;
    final dst = Rect.fromCenter(center: const Offset(w / 2, 400), width: img.width.toDouble(), height: img.height.toDouble());
    // Het merk is crème; in goud gieten met een verloop.
    c.saveLayer(dst, Paint());
    c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.high);
    c.drawRect(
      dst,
      Paint()
        ..blendMode = BlendMode.srcIn
        ..shader = ui.Gradient.linear(dst.topLeft, dst.bottomRight, [goldLight, gold, goldDeep]),
    );
    c.restore();
  } catch (_) {
    // Zonder logo is de kaart nog steeds bruikbaar.
  }

  void text(String s, double y, {double size = 40, Color color = gold, FontWeight weight = FontWeight.w700, double spacing = 0, String? font}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontFamily: font ?? RwFonts.display, fontSize: size, color: color, fontWeight: weight, letterSpacing: spacing),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(minWidth: w - 160, maxWidth: w - 160);
    tp.paint(c, Offset(80, y));
  }

  text('KADANS', 660, size: 30, spacing: 14, weight: FontWeight.w800);
  text(name.isEmpty ? 'Loop met mij mee' : '$name nodigt je uit', 730, size: 54, color: pal.text, weight: FontWeight.w800);
  text('om samen te lopen', 800, size: 34, color: pal.muted, weight: FontWeight.w500, font: RwFonts.body);

  // De code in een gouden kader.
  const boxW = 620.0, boxH = 150.0;
  final box = RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(w / 2, 1000), width: boxW, height: boxH), const Radius.circular(28));
  c.drawRRect(box, Paint()..color = pal.surface);
  c.drawRRect(
    box,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..shader = ui.Gradient.linear(Offset(w / 2 - boxW / 2, 0), Offset(w / 2 + boxW / 2, 0), [goldDeep, goldLight, goldDeep]),
  );
  text('VRIENDCODE', 944, size: 22, color: pal.subtle, spacing: 6, weight: FontWeight.w700);
  text(code.split('').join(' '), 978, size: 64, color: goldLight, weight: FontWeight.w800, spacing: 4);

  text('Open de link of vul de code in bij Uitdagingen → Samen', 1150, size: 28, color: pal.muted, weight: FontWeight.w500, font: RwFonts.body);

  // Kleine sterretjes voor wat glans.
  final sparkle = Paint()..color = goldLight.withValues(alpha: 0.7);
  for (final (x, y, r) in const [(170.0, 190.0, 5.0), (905.0, 250.0, 4.0), (860.0, 610.0, 3.0), (210.0, 640.0, 3.5)]) {
    final p = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final rr = i.isEven ? r * 3 : r * 0.8;
      final pt = Offset(x + rr * math.cos(a), y + rr * math.sin(a));
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    c.drawPath(p..close(), sparkle);
  }

  final img = await rec.endRecording().toImage(w.round(), h.round());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Deelt de luxe uitnodiging: kaart + tekst met link.
Future<void> shareInvite({required String code, required String name}) async {
  final link = inviteLink(code);
  final text = 'Loop je mee in Kadans? Tik op de link om me toe te voegen: $link (of vul mijn code $code in bij Uitdagingen → Samen).';
  try {
    final png = await inviteCardPng(code: code, name: name);
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(png, mimeType: 'image/png', name: 'kadans-uitnodiging.png')],
      text: text,
      subject: 'Loop mee in Kadans',
    ));
  } catch (_) {
    await SharePlus.instance.share(ShareParams(text: text, subject: 'Loop mee in Kadans'));
  }
}

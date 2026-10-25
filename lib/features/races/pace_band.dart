import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/zones.dart';

/// Tekent een tempobandje als PNG (smal en lang, om te printen of als achtergrond op je telefoon).
/// Per kilometer: km, tempo en de tijd die je dan op de klok moet hebben.
Future<Uint8List> paceBandPng({
  required String title,
  required String subtitle,
  required List<PlannedSplit> plan,
}) async {
  const width = 480.0, rowH = 46.0, headH = 130.0, footH = 50.0;
  final height = headH + rowH * plan.length + footH;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, Rect.fromLTWH(0, 0, width, height));
  c.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = RwColors.background);
  c.drawRect(const Rect.fromLTWH(0, 0, width, 8), Paint()..color = RwColors.accent);

  void text(String s, double x, double y,
      {double size = 20, Color? color, FontWeight weight = FontWeight.w600, double? maxW, TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: size, color: color ?? RwColors.text, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(minWidth: maxW ?? 0, maxWidth: maxW ?? width - x - 20);
    tp.paint(c, Offset(x, y));
  }

  text('KADANS · TEMPOBAND', 24, 22, size: 14, color: RwColors.accent, weight: FontWeight.w800);
  text(title, 24, 44, size: 28, weight: FontWeight.w800);
  text(subtitle, 24, 82, size: 16, color: RwColors.muted, weight: FontWeight.w500);
  for (var i = 0; i < plan.length; i++) {
    final sp = plan[i];
    final y = headH + i * rowH;
    if (i.isOdd) c.drawRect(Rect.fromLTWH(0, y, width, rowH), Paint()..color = RwColors.surface);
    final label = sp.meters < 999 ? (sp.km - 1 + sp.meters / 1000).toStringAsFixed(1).replaceAll('.', ',') : 'km ${sp.km}';
    text(label, 24, y + 10, size: 20, color: RwColors.subtle);
    text(Fmt.pace(sp.pace), 150, y + 9, size: 22, weight: FontWeight.w800);
    text(Fmt.duration(sp.cumulative.round()), 300, y + 9, size: 22, color: RwColors.accentLight, maxW: 156, align: TextAlign.right);
  }
  text('Succes! Begin rustig, eindig sterk.', 24, height - footH + 14, size: 15, color: RwColors.subtle, weight: FontWeight.w500);

  final img = await rec.endRecording().toImage(width.round(), height.round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

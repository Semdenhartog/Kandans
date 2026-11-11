import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/i18n.dart';
import '../../domain/custom_plan.dart';
import '../../domain/training_plan.dart';

/// Het hele schema op maat als PDF (A4, papierwit met goud en espresso), en delen/opslaan.
Future<void> shareCustomPlanPdf(CustomPlan plan) async {
  final bytes = await buildCustomPlanPdf(plan);
  final dir = await getTemporaryDirectory();
  final name = 'kadans-schema-${plan.wishes.goal.name}.pdf';
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/pdf', name: name)],
    subject: tr('Mijn hardloopschema van Kadans'),
  ));
}

const _paper = PdfColor.fromInt(0xFFFAF6EF);
const _ink = PdfColor.fromInt(0xFF211A13);
const _muted = PdfColor.fromInt(0xFF5A5044);
const _subtle = PdfColor.fromInt(0xFF8A7E6E);
const _gold = PdfColor.fromInt(0xFFB8955F);
const _goldLight = PdfColor.fromInt(0xFFEFE2C8);
const _line = PdfColor.fromInt(0xFFDCD1BF);
const _espresso = PdfColor.fromInt(0xFF13110E);

const _days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
const _months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
String _d(DateTime d) => '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

PdfColor _kind(SessionKind k) => switch (k) {
      SessionKind.easy => const PdfColor.fromInt(0xFF4E8A5C),
      SessionKind.long => const PdfColor.fromInt(0xFF4F7AA8),
      SessionKind.tempo => const PdfColor.fromInt(0xFFB58A1E),
      SessionKind.interval => _gold,
      SessionKind.race => const PdfColor.fromInt(0xFFA93A35),
    };

PdfColor _phase(PlanPhase p) => switch (p) {
      PlanPhase.start || PlanPhase.basis => const PdfColor.fromInt(0xFF8A9A7E),
      PlanPhase.opbouw => const PdfColor.fromInt(0xFFA88E62),
      PlanPhase.piek => _gold,
      PlanPhase.afbouw => const PdfColor.fromInt(0xFF7E9DBF),
      PlanPhase.herstel => const PdfColor.fromInt(0xFF7FB08A),
      PlanPhase.vrij => _line,
    };

Future<Uint8List> buildCustomPlanPdf(CustomPlan plan) async {
  Future<pw.Font> font(String path) async => pw.Font.ttf(await rootBundle.load(path));
  final display = await font('assets/fonts/Saira-ExtraBold.ttf');
  final displayBold = await font('assets/fonts/Saira-Bold.ttf');
  final body = await font('assets/fonts/DMSans-Regular.ttf');
  final bodyBold = await font('assets/fonts/DMSans-Bold.ttf');
  final mono = await font('assets/fonts/DejaVuSansMono.ttf');

  final w = plan.wishes;
  final title = w.raceName ?? tr(w.goal.label);
  final end = plan.raceDate ?? plan.weeks.last.start.add(const Duration(days: 6));
  final doc = pw.Document(title: 'Kadans – ${tr('Schema op maat')}', author: 'Kadans');
  final theme = pw.ThemeData.withFont(base: body, bold: bodyBold);

  pw.Widget label(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
        child: pw.Text(t, style: pw.TextStyle(font: mono, fontSize: 8, letterSpacing: 1.4, color: _subtle)),
      );

  pw.Widget stat(String value, String text) => pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(value, style: pw.TextStyle(font: display, fontSize: 22, color: _ink)),
          pw.Text(text, style: const pw.TextStyle(fontSize: 8, color: _subtle)),
        ]),
      );

  final page = pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 44),
    theme: theme,
    buildBackground: (_) => pw.FullPage(ignoreMargins: true, child: pw.Container(color: _paper)),
  );

  // Voorblad met samenvatting.
  doc.addPage(pw.Page(
    pageTheme: page,
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(26, 26, 26, 24),
        decoration: const pw.BoxDecoration(color: _espresso, borderRadius: pw.BorderRadius.all(pw.Radius.circular(14))),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            pw.Container(width: 8, height: 8, color: const PdfColor.fromInt(0xFFD9BF92)),
            pw.SizedBox(width: 8),
            pw.Text('KADANS  ·  ${tr('SCHEMA OP MAAT')}', style: pw.TextStyle(font: mono, fontSize: 8, letterSpacing: 1.6, color: const PdfColor.fromInt(0xFF94897A))),
          ]),
          pw.SizedBox(height: 18),
          pw.Text(title, style: pw.TextStyle(font: display, fontSize: 38, color: const PdfColor.fromInt(0xFFD9BF92))),
          pw.SizedBox(height: 4),
          pw.Text('${_d(plan.start)} – ${_d(end)}  ·  ${tr(w.ambition.label)}${w.name == null ? '' : '  ·  ${w.name}'}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFFBDB1A0))),
          if (w.goalTimeSeconds != null && plan.goalCheck != null) ...[
            pw.SizedBox(height: 10),
            pw.Text('${tr('Doeltijd')} ${fmtTime(w.goalTimeSeconds!)}  ·  ${tr(plan.goalCheck!)}',
                style: pw.TextStyle(font: bodyBold, fontSize: 10, color: const PdfColor.fromInt(0xFFD9BF92))),
          ],
        ]),
      ),
      pw.SizedBox(height: 18),
      pw.Row(children: [
        stat('${plan.weeks.length}', tr('weken')),
        stat('${plan.peakKm.round()}', tr('km piekweek')),
        stat('${plan.totalKm.round()}', tr('km in totaal')),
        stat('${plan.keyCount}', tr('sleuteltrainingen')),
        if (plan.predictedSeconds != null) stat(fmtTime(plan.predictedSeconds!), tr('verwachte tijd')),
      ]),
      for (final warn in plan.warnings)
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: _goldLight, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
          child: pw.Text(tr(warn), style: const pw.TextStyle(fontSize: 9, color: _ink, lineSpacing: 2)),
        ),
      label('01  ${tr('FASES')}'),
      pw.Row(children: [
        for (final wk in plan.weeks) pw.Expanded(child: pw.Container(height: 10, margin: const pw.EdgeInsets.only(right: 1.5), color: _phase(wk.phase))),
      ]),
      pw.SizedBox(height: 6),
      pw.Wrap(spacing: 12, runSpacing: 4, children: [
        for (final p in {for (final wk in plan.weeks) wk.phase})
          pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
            pw.Container(width: 6, height: 6, color: _phase(p)),
            pw.SizedBox(width: 4),
            pw.Text('${tr(p.label)}: ${tr(p.subtitle)}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ]),
      ]),
      label('02  ${tr('KILOMETERS PER WEEK')}'),
      pw.SizedBox(
        height: 70,
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          for (final wk in plan.weeks)
            pw.Expanded(
              child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                pw.Text(wk.km.toStringAsFixed(0), style: const pw.TextStyle(fontSize: 6, color: _subtle)),
                pw.SizedBox(height: 2),
                pw.Container(
                  height: 2 + 52 * (plan.peakKm <= 0 ? 0 : wk.km / plan.peakKm),
                  margin: const pw.EdgeInsets.symmetric(horizontal: 1.5),
                  color: wk.recovery || wk.phase == PlanPhase.vrij ? _line : _phase(wk.phase),
                ),
              ]),
            ),
        ]),
      ),
      label('03  ${tr('JOUW TEMPO\'S')}'),
      pw.Table(
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
        columnWidths: const {0: pw.FlexColumnWidth(1.1), 1: pw.FlexColumnWidth(1.1), 2: pw.FlexColumnWidth(0.7), 3: pw.FlexColumnWidth(3)},
        children: [
          for (final z in plan.paces)
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text(tr(z.name), style: pw.TextStyle(font: bodyBold, fontSize: 10, color: _ink))),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6),
                child: pw.Text('${fmtPace(z.from)}–${fmtPace(z.to)} /km', style: pw.TextStyle(font: displayBold, fontSize: 10, color: _gold)),
              ),
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text('${tr('zwaarte')} ${z.rpe}', style: const pw.TextStyle(fontSize: 8, color: _subtle))),
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text(tr(z.text), style: const pw.TextStyle(fontSize: 8, color: _muted))),
            ]),
        ],
      ),
      if (plan.paceIsEstimate)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(tr('Tempo\'s zijn een schatting: je hebt nog weinig runs. Loop op gevoel (zwaarte).'), style: const pw.TextStyle(fontSize: 8, color: _subtle)),
        ),
      pw.Spacer(),
      pw.Text(tr('Zwaarte 1–10: 3–4 = je kunt praten, 7 = losse woorden, 9–10 = alles geven. Mis je een training? Niet inhalen, gewoon verder.'),
          style: const pw.TextStyle(fontSize: 8, color: _subtle)),
    ]),
  ));

  // Alle weken.
  doc.addPage(pw.MultiPage(
    pageTheme: page,
    footer: (ctx) => pw.Row(children: [
      pw.Text('KADANS  ·  ${title.toUpperCase()}', style: pw.TextStyle(font: mono, fontSize: 7, letterSpacing: 1.2, color: _subtle)),
      pw.Spacer(),
      pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: pw.TextStyle(font: mono, fontSize: 7, color: _subtle)),
    ]),
    build: (ctx) => [
      for (final wk in plan.weeks) _week(wk, display: display, bodyBold: bodyBold, mono: mono),
      if (plan.raceDay.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Text(tr('Wedstrijdplan'), style: pw.TextStyle(font: display, fontSize: 18, color: _ink)),
        pw.SizedBox(height: 8),
        for (final (i, line) in plan.raceDay.indexed)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(width: 20, child: pw.Text((i + 1).toString().padLeft(2, '0'), style: pw.TextStyle(font: mono, fontSize: 8, color: _gold))),
              pw.Expanded(child: pw.Text(tr(line), style: const pw.TextStyle(fontSize: 9, color: _ink, lineSpacing: 2))),
            ]),
          ),
      ],
      pw.SizedBox(height: 14),
      pw.Text(tr('Pijn die erger wordt of blijft? Stop, rust en vraag een fysiotherapeut of je huisarts. Het schema is een richtlijn, je lichaam beslist.'),
          style: const pw.TextStyle(fontSize: 8, color: _subtle)),
    ],
  ));
  return doc.save();
}

pw.Widget _week(PlanWeek wk, {required pw.Font display, required pw.Font bodyBold, required pw.Font mono}) {
  final rows = <(DateTime, pw.TableRow)>[
    for (final it in wk.items)
      (
        it.session.date,
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.top,
          children: [
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 5), child: pw.Text(_d(it.session.date), style: pw.TextStyle(font: mono, fontSize: 7.5, color: _muted))),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 5),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Container(width: 2.5, height: 22, color: _kind(it.session.kind)),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('${it.session.title}${it.key ? '  *' : ''}', style: pw.TextStyle(font: bodyBold, fontSize: 9, color: _ink)),
                    pw.SizedBox(height: 1.5),
                    pw.Text(it.parts.join('  ·  '), style: const pw.TextStyle(fontSize: 7.5, color: _muted, lineSpacing: 1.5)),
                  ]),
                ),
              ]),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 5),
              child: pw.Text('${it.minutes} min', textAlign: pw.TextAlign.right, style: pw.TextStyle(font: bodyBold, fontSize: 8.5, color: _ink)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 5),
              child: pw.Text('${it.rpe}/10', textAlign: pw.TextAlign.right, style: pw.TextStyle(font: bodyBold, fontSize: 8.5, color: _kind(it.session.kind))),
            ),
          ],
        ),
      ),
    for (final e in wk.extras)
      (
        e.date,
        pw.TableRow(children: [
          pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Text(_d(e.date), style: pw.TextStyle(font: mono, fontSize: 7.5, color: _subtle))),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Text(e.kind == ExtraKind.rust ? e.title : '${e.title}: ${e.description}', style: const pw.TextStyle(fontSize: 7.5, color: _subtle)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Text(e.minutes > 0 ? '${e.minutes} min' : '', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8, color: _subtle)),
          ),
          pw.SizedBox(),
        ]),
      ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 12),
    padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _line, width: 0.7),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
    ),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text('${tr('WEEK')} ${wk.number.toString().padLeft(2, '0')}', style: pw.TextStyle(font: display, fontSize: 15, color: _ink)),
        pw.SizedBox(width: 10),
        pw.Container(width: 6, height: 6, margin: const pw.EdgeInsets.only(bottom: 4), color: _phase(wk.phase)),
        pw.SizedBox(width: 4),
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Text(tr(wk.phase.label).toUpperCase() + (wk.recovery && wk.phase != PlanPhase.herstel ? '  ·  ${tr('RUSTWEEK')}' : ''),
              style: pw.TextStyle(font: mono, fontSize: 7.5, letterSpacing: 1.2, color: _muted)),
        ),
        pw.Spacer(),
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Text('${_d(wk.start)}  ·  ${wk.km.toStringAsFixed(0)} km  ·  ${wk.minutes} min', style: pw.TextStyle(font: mono, fontSize: 7.5, color: _subtle)),
        ),
      ]),
      pw.SizedBox(height: 4),
      pw.Text(tr(wk.focus), style: const pw.TextStyle(fontSize: 8, color: _muted)),
      pw.SizedBox(height: 4),
      pw.Table(
        columnWidths: const {0: pw.FixedColumnWidth(58), 1: pw.FlexColumnWidth(), 2: pw.FixedColumnWidth(40), 3: pw.FixedColumnWidth(30)},
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.4)),
        children: [for (final r in rows) r.$2],
      ),
    ]),
  );
}

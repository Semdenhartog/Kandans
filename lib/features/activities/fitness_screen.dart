import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/heart_rate_service.dart';
import '../../domain/training_load.dart';
import '../../shared/reveal.dart';
import '../../shared/widgets.dart';

void openFitness(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FitnessScreen()));
}

/// Fitheid, vermoeidheid en vorm over de laatste 90 dagen.
class FitnessScreen extends ConsumerWidget {
  const FitnessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final series = fitnessSeries(runs, DateTime.now(), days: 90, maxHr: HeartRateService.instance.maxHr.value);
    final today = series.isEmpty ? null : series.last;
    final weekAgo = series.length > 7 ? series[series.length - 8] : null;
    final advice = today == null ? null : formAdvice(today);
    return Scaffold(
      appBar: AppBar(title: const Text('Fitheid en vorm')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (today == null || advice == null)
            EmptyState(icon: Icons.show_chart, title: 'Nog geen gegevens', message: 'Loop een paar runs, dan zie je hier je fitheid.')
          else ...[
            RwCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(advice.title, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 28, fontWeight: FontWeight.w800, color: RwColors.accent)),
                  const SizedBox(height: 4),
                  Text(advice.text, style: const TextStyle(color: RwColors.muted, height: 1.4)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: StatTile(label: 'Fitheid', value: today.fitness.round().toString())),
                      const SizedBox(width: 8),
                      Expanded(child: StatTile(label: 'Vermoeidheid', value: today.fatigue.round().toString())),
                      const SizedBox(width: 8),
                      Expanded(child: StatTile(label: 'Vorm', value: '${today.form >= 0 ? '+' : ''}${today.form.round()}')),
                    ],
                  ),
                  if (weekAgo != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Fitheid ${today.fitness >= weekAgo.fitness ? '+' : ''}${(today.fitness - weekAgo.fitness).round()} ten opzichte van een week geleden.',
                      style: const TextStyle(color: RwColors.subtle, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            RwCard(
              title: 'LAATSTE 90 DAGEN',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label: 'Grafiek van fitheid en vermoeidheid. Fitheid nu ${today.fitness.round()}, vermoeidheid ${today.fatigue.round()}.',
                    excludeSemantics: true,
                    child: SizedBox(height: 180, child: RevealIn(child: CustomPaint(painter: _FitnessPainter(series), size: Size.infinite))),
                  ),
                  const SizedBox(height: 8),
                  const Wrap(
                    spacing: 16,
                    children: [
                      _Legend(color: RwColors.accent, label: 'Fitheid'),
                      _Legend(color: Color(0xFF8D8D98), label: 'Vermoeidheid'),
                      _Legend(color: Color(0xFF6E6E78), label: 'Belasting per dag'),
                    ],
                  ),
                ],
              ),
            ),
            if (intensityBalance(runs, now: DateTime.now(), maxHr: HeartRateService.instance.maxHr.value) case final b?) ...[
              const SizedBox(height: 12),
              RwCard(
                title: 'RUSTIG EN STEVIG · 4 WEKEN',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 14,
                        child: Row(
                          children: [
                            Expanded(flex: (b.easyShare * 100).round().clamp(1, 99), child: Container(color: RwColors.good)),
                            Expanded(flex: (100 - b.easyShare * 100).round().clamp(1, 99), child: Container(color: RwColors.warning)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('Rustig ${(b.easyShare * 100).round()}%', style: const TextStyle(color: RwColors.good, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('Stevig ${(100 - b.easyShare * 100).round()}%', style: const TextStyle(color: RwColors.warning, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(b.advice, style: const TextStyle(color: RwColors.muted, height: 1.4)),
                    const SizedBox(height: 4),
                    const Text(
                      'Goede lopers doen zo\'n 80% van hun tijd rustig. Rustig = onder 80% van je maximale hartslag, of zonder hartslag duidelijk trager dan je drempeltempo.',
                      style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            const RwCard(
              title: 'HOE WERKT DIT?',
              child: Text(
                'Elke run krijgt een belasting: hoe lang en hoe zwaar (op hartslag als je een band of horloge gebruikt, anders op tempo). '
                'Fitheid is je gemiddelde belasting van de laatste 6 weken, vermoeidheid die van de laatste week. '
                'Vorm is het verschil: positief betekent fris, negatief betekent dat je flink traint. '
                'Rond de -10 tot -30 word je sterker; veel lager is een teken om rust te nemen.',
                style: TextStyle(color: RwColors.muted, height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: RwColors.subtle, fontSize: 12)),
      ]);
}

class _FitnessPainter extends CustomPainter {
  _FitnessPainter(this.days);
  final List<FitnessDay> days;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.length < 2) return;
    var maxV = 10.0;
    for (final d in days) {
      if (d.fitness > maxV) maxV = d.fitness;
      if (d.fatigue > maxV) maxV = d.fatigue;
      if (d.load > maxV) maxV = d.load;
    }
    maxV *= 1.1;
    const bottom = 16.0;
    final h = size.height - bottom;
    double x(int i) => i / (days.length - 1) * size.width;
    double y(double v) => h - v / maxV * h;

    final grid = Paint()
      ..color = RwColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h), Offset(size.width, h), grid);

    // Belasting per dag als dunne staafjes.
    // Neutraal grijs: de oranje fitheidslijn is waar het om draait.
    final bar = Paint()..color = const Color(0xFF6E6E78).withValues(alpha: 0.45);
    final w = (size.width / days.length).clamp(1.0, 4.0);
    for (var i = 0; i < days.length; i++) {
      if (days[i].load <= 0) continue;
      canvas.drawRect(Rect.fromLTRB(x(i) - w / 2, y(days[i].load), x(i) + w / 2, h), bar);
    }

    void line(double Function(FitnessDay) v, Color c, double width) {
      final p = Path()..moveTo(x(0), y(v(days.first)));
      for (var i = 1; i < days.length; i++) {
        p.lineTo(x(i), y(v(days[i])));
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Zachte oranje vulling onder de fitheidslijn.
    final fill = Path()..moveTo(x(0), h);
    for (var i = 0; i < days.length; i++) {
      fill.lineTo(x(i), y(days[i].fitness));
    }
    fill
      ..lineTo(x(days.length - 1), h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [RwColors.accent.withValues(alpha: 0.28), RwColors.accent.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, h)),
    );
    // Gloed onder de lijn zelf.
    final glowPath = Path()..moveTo(x(0), y(days.first.fitness));
    for (var i = 1; i < days.length; i++) {
      glowPath.lineTo(x(i), y(days[i].fitness));
    }
    canvas.drawPath(
      glowPath,
      Paint()
        ..color = RwColors.accent.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    line((d) => d.fatigue, const Color(0xFF8D8D98), 1.6);
    line((d) => d.fitness, RwColors.accent, 2.6);

    // Maandlabels.
    const months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];
    for (var i = 0; i < days.length; i++) {
      if (days[i].day.day != 1) continue;
      final tp = TextPainter(
        text: TextSpan(text: months[days[i].day.month - 1], style: const TextStyle(fontFamily: RwFonts.body, color: RwColors.subtle, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((x(i) - tp.width / 2).clamp(0, size.width - tp.width), h + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _FitnessPainter old) => old.days != days;
}

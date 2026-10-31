import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/forecast_confidence_service.dart';
import '../../domain/forecast_confidence.dart';

/// "Hoe zeker is dit moment?" onder de grote tijd op Vandaag.
/// Bewaart ook wat Kadans voorspelde, zodat we achteraf kunnen zien of het klopte.
class ConfidenceChip extends ConsumerStatefulWidget {
  const ConfidenceChip({
    super.key,
    required this.lat,
    required this.lon,
    required this.start,
    required this.minutes,
    required this.weather,
    required this.isBest,
  });

  final double lat, lon;
  final DateTime start;
  final int minutes;
  final HourWeather weather;
  final bool isBest;

  @override
  ConsumerState<ConfidenceChip> createState() => _ConfidenceChipState();
}

class _ConfidenceChipState extends ConsumerState<ConfidenceChip> {
  @override
  void initState() {
    super.initState();
    _remember();
  }

  @override
  void didUpdateWidget(ConfidenceChip old) {
    super.didUpdateWidget(old);
    if (old.start != widget.start || old.isBest != widget.isBest) _remember();
  }

  void _remember() {
    if (!widget.isBest) return;
    final w = widget.weather;
    ForecastCheckStore.remember(ForecastSnapshot(
      time: widget.start,
      lat: widget.lat,
      lon: widget.lon,
      temp: w.temperature,
      rainChance: w.precipitationProbability ?? 0,
      rainMm: w.precipitation ?? 0,
      wind: w.windSpeed,
    )).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final args = (lat: widget.lat, lon: widget.lon, start: widget.start, minutes: widget.minutes);
    final c = ref.watch(forecastConfidenceProvider(args)).value;
    if (c == null) return const SizedBox.shrink();
    final (color, icon, text) = _look(c);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        button: true,
        label: text,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _sheet(context, c),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(child: Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      ),
    );
  }

  (Color, IconData, String) _look(ForecastConfidence c) {
    switch (c.level) {
      case ConfidenceLevel.sure:
        return (RwColors.good, Icons.verified_outlined, c.mostlyDry ? tr('Zeker droog') : tr('Zeker nat, regenjas mee'));
      case ConfidenceLevel.likely:
        return (RwColors.accent, Icons.check_circle_outline, c.mostlyDry ? tr('Vrij zeker droog') : tr('Waarschijnlijk regen'));
      case ConfidenceLevel.shaky:
        final at = c.recheckAt;
        return (
          RwColors.warning,
          Icons.help_outline,
          at == null ? tr('Kan nog omslaan') : trf('Kan omslaan, kijk om {tijd} nog even', {'tijd': Fmt.time(at)}),
        );
    }
  }

  void _sheet(BuildContext context, ForecastConfidence c) {
    final pct = (c.wetShare * 100).round();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Hoe zeker is dit moment?'), style: RwText.title),
            const SizedBox(height: 10),
            Text(
              trf('Kadans liet het weer {n} keer doorrekenen met kleine verschillen. In {pct}% daarvan regent het tijdens je run.',
                  {'n': '${c.members}', 'pct': '$pct'}),
              style: TextStyle(color: RwColors.muted, height: 1.4),
            ),
            const SizedBox(height: 6),
            Text(
              trf('De temperatuur verschilt hooguit {graden} graden tussen de varianten.', {'graden': c.tempSpread.toStringAsFixed(1)}),
              style: TextStyle(color: RwColors.muted, height: 1.4),
            ),
            if (c.recheckAt != null) ...[
              const SizedBox(height: 6),
              Text(
                trf('Twijfel? Kijk om {tijd} nog even. Dan is de verwachting veel scherper.', {'tijd': Fmt.time(c.recheckAt!)}),
                style: TextStyle(color: RwColors.text, height: 1.4),
              ),
            ],
            const SizedBox(height: 16),
            Text(tr('Klopte de voorspelling?'), style: TextStyle(fontWeight: FontWeight.w700, color: RwColors.text)),
            const SizedBox(height: 6),
            Consumer(builder: (_, ref, _) {
              final s = ref.watch(forecastScoreProvider);
              return Text(
                switch (s.value) {
                  (final hit, final total) when total >= 3 =>
                    trf('Afgelopen 30 dagen klopte het beste moment {goed} van de {totaal} keer (droog of nat, en binnen 2,5 graad).',
                        {'goed': '$hit', 'totaal': '$total'}),
                  _ => tr('Kadans houdt bij of het beste moment klopte. Na een paar dagen zie je hier hoe vaak.'),
                },
                style: TextStyle(color: RwColors.muted, height: 1.4),
              );
            }),
          ]),
        ),
      ),
    );
  }
}

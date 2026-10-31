import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/kadans_effect_store.dart';
import '../../domain/bingo.dart';
import '../../shared/widgets.dart';

/// Loop-bingo op Vandaag: negen vakjes, elke maand nieuw.
class BingoCardView extends ConsumerStatefulWidget {
  const BingoCardView({super.key});

  @override
  ConsumerState<BingoCardView> createState() => _BingoCardViewState();
}

class _BingoCardViewState extends ConsumerState<BingoCardView> {
  bool _celebrate = false;
  String? _checkedFor;

  /// Laat één keer "Bingo!" zien als er sinds de vorige keer een lijn bij kwam.
  Future<void> _checkNewLines(BingoCard card) async {
    final key = 'bingo_lines_${card.month.year}_${card.month.month}';
    final sig = '$key:${card.lines}';
    if (_checkedFor == sig) return;
    _checkedFor = sig;
    final p = await SharedPreferences.getInstance();
    final before = p.getInt(key) ?? 0;
    if (card.lines > before) {
      await p.setInt(key, card.lines);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _celebrate = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runs = ref.watch(activitiesProvider).value;
    if (runs == null) return const SizedBox.shrink();
    final wise = ref.watch(kadansEffectProvider).value?.wellChosenIds ?? const <String>{};
    final card = bingoFor(DateTime.now(), runs, wellChosen: wise);
    _checkNewLines(card);
    final win = card.winning;
    final month = DateFormat('MMMM', LanguageController.instance.lang.intlLocale).format(card.month);

    final status = card.full
        ? tr('Volle kaart! Knap gedaan.')
        : card.lines > 0
            ? trf('Bingo! {n} volle lijn(en). Lukt de hele kaart?', {'n': '${card.lines}'})
            : trf('{n} van 8 vakjes. Drie op een rij is bingo.', {'n': '${card.doneCount}'});

    return RwCard(
      title: trf('LOOP-BINGO · {maand}', {'maand': month.toUpperCase()}),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_celebrate && card.lines > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Icon(Icons.celebration_outlined, color: RwColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('Bingo! Je hebt een nieuwe lijn vol.'),
                    style: TextStyle(color: RwColors.accent, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (var i = 0; i < 9; i++) _Cell(cell: card.cells[i], inLine: win.contains(i)),
          ],
        ),
        const SizedBox(height: 10),
        Text(status, style: TextStyle(color: RwColors.muted, fontSize: 13)),
      ]),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.cell, required this.inLine});
  final BingoCell cell;
  final bool inLine;

  @override
  Widget build(BuildContext context) {
    final t = cell.task;
    final done = cell.done;
    final color = inLine ? RwColors.accent : (done ? RwColors.good : RwColors.subtle);
    final label = t == null ? 'Kadans' : tr(t.label);
    return Semantics(
      button: t != null,
      label: '$label${done ? ', ${tr('gedaan')}' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: t == null
            ? null
            : () => showMessage(
                  context,
                  cell.doneAt == null
                      ? tr(t.hint)
                      : trf('{opdracht} Gelukt op {datum}.', {'opdracht': tr(t.hint), 'datum': Fmt.date(cell.doneAt!)}),
                ),
        child: Container(
          decoration: BoxDecoration(
            color: done ? color.withValues(alpha: 0.14) : RwColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: done ? color.withValues(alpha: 0.6) : RwColors.subtle.withValues(alpha: 0.25)),
          ),
          child: Stack(children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                      fontFamily: t == null ? RwFonts.display : null,
                      color: done ? RwColors.text : RwColors.muted,
                    ),
                  ),
                ),
              ),
            ),
            if (done && t != null)
              Positioned(top: 4, right: 4, child: Icon(Icons.check_circle, size: 14, color: color)),
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../domain/start_time_scoring.dart';
import '../../domain/verdict.dart';

/// Uitleg bij het advies: waarom dit het beste moment is en hoe "nu" ervoor staat.
void showWhySheet(BuildContext context, RunVerdict v) {
  Widget block(String head, StartTimeScore sc) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(head, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          for (final r in sc.reasons.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('•  $r', style: TextStyle(color: RwColors.muted, height: 1.35)),
            ),
        ],
      );
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            block(trf('Beste moment: {t} (score {s})', {'t': Fmt.time(v.best.start), 's': '${v.best.score}'}), v.best),
            if (v.now.reasons.isNotEmpty && v.now.start != v.best.start) ...[
              const SizedBox(height: 14),
              block(trf('Nu (score {s})', {'s': '${v.now.score}'}), v.now),
            ],
            const SizedBox(height: 14),
            Text(
              tr('De score telt temperatuur, wind, regen, licht en je eigen gewoontes mee. Hoger is beter.'),
              style: TextStyle(color: RwColors.subtle, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    ),
  );
}

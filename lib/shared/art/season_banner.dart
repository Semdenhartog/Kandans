import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'landscape.dart';

/// Seizoensplaatje: elke maand een ander landschap met een korte zin.
class SeasonBanner extends StatelessWidget {
  const SeasonBanner({super.key, this.height = 104});
  final double height;

  static const _lines = {
    1: 'Koud en helder. Rustig opwarmen en laagjes aan.',
    2: 'Nog even winter. Elke run telt dubbel.',
    3: 'De dagen worden langer. Krokussen langs het pad.',
    4: 'Tulpentijd. Lente in je benen.',
    5: 'Bloesem en lange avonden. Ideaal loopweer.',
    6: 'Vroeg licht. Loop voor de warmte uit.',
    7: 'Zomer. Drink genoeg en zoek de schaduw.',
    8: 'De hei kleurt paars. Pak de vroege ochtend.',
    9: 'Koelere ochtenden. Tijd voor een record?',
    10: 'Vallende bladeren. Kijk uit voor gladde plekken.',
    11: 'Mist en vroege schemer. Zichtbaar blijven.',
    12: 'Donkere dagen. Kadans zoekt je lichtste moment.',
  };

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = DateFormat('MMMM', LanguageController.instance.lang.intlLocale).format(now);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [RwColors.accent.withValues(alpha: 0.16), RwColors.surface],
          ),
          border: Border.all(color: RwColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(children: [
          Positioned.fill(child: KadansLandscape(date: now, opacity: 0.9)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 44),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(month.toUpperCase(), style: RwText.overline),
              const SizedBox(height: 2),
              Text(tr(_lines[now.month]!), style: TextStyle(fontWeight: FontWeight.w600, color: RwColors.text, height: 1.3)),
            ]),
          ),
        ]),
      ),
    );
  }
}

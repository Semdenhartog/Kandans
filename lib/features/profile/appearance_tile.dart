import 'package:flutter/material.dart';

import '../../core/appearance.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../../core/i18n.dart';
import '../../shared/language_picker.dart';

/// Ik → Weergave: Automatisch (volgt je telefoon), Licht of Donker.
class AppearanceTile extends StatelessWidget {
  const AppearanceTile({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppearanceController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            TileIcon(Icons.contrast),
            SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Weergave'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: RwColors.text)),
                SizedBox(height: 2),
                Text(
                  switch (c.mode) {
                    Appearance.system => tr('Volgt je telefoon: licht overdag, donker als je telefoon op donker staat.'),
                    Appearance.light => tr('Altijd Zand: licht en rustig, goed leesbaar buiten.'),
                    Appearance.dark => tr('Altijd Zand avond: donker, prettig in het donker.'),
                  },
                  style: TextStyle(fontSize: 13, color: RwColors.subtle, height: 1.35),
                ),
              ]),
            ),
          ]),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<Appearance>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: Appearance.system, label: Text(tr('Auto'))),
                ButtonSegment(value: Appearance.light, label: Text(tr('Licht'))),
                ButtonSegment(value: Appearance.dark, label: Text(tr('Donker'))),
              ],
              selected: {c.mode},
              onSelectionChanged: (v) => c.set(v.first),
            ),
          ),
          SizedBox(height: 14),
          Row(children: [
            Expanded(child: Text(tr('Taal'), style: TextStyle(fontSize: 13, color: RwColors.subtle, fontWeight: FontWeight.w600))),
            const LanguageButton(),
          ]),
          SizedBox(height: 8),
          Text(tr('Openen op'), style: TextStyle(fontSize: 13, color: RwColors.subtle, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final e in AppearanceController.startTabs.entries) ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: {c.startTab},
              onSelectionChanged: (v) => c.setStartTab(v.first),
            ),
          ),
        ]),
      ),
    );
  }
}

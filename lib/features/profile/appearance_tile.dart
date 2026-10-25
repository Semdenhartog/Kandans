import 'package:flutter/material.dart';

import '../../core/appearance.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Ik → Weergave: Automatisch (volgt je telefoon), Licht of Donker.
class AppearanceTile extends StatelessWidget {
  const AppearanceTile({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppearanceController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const TileIcon(Icons.contrast),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Weergave', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: RwColors.text)),
                const SizedBox(height: 2),
                Text(
                  switch (c.mode) {
                    Appearance.system => 'Volgt je telefoon: licht overdag, donker als je telefoon op donker staat.',
                    Appearance.light => 'Altijd Zand: licht en rustig, goed leesbaar buiten.',
                    Appearance.dark => 'Altijd Zand avond: donker, prettig in het donker.',
                  },
                  style: TextStyle(fontSize: 13, color: RwColors.subtle, height: 1.35),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<Appearance>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Appearance.system, label: Text('Auto')),
                ButtonSegment(value: Appearance.light, label: Text('Licht')),
                ButtonSegment(value: Appearance.dark, label: Text('Donker')),
              ],
              selected: {c.mode},
              onSelectionChanged: (v) => c.set(v.first),
            ),
          ),
        ]),
      ),
    );
  }
}

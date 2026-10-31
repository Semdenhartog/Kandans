import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../data/services/media_button_service.dart';

/// Schakelaar: knop op je oortjes gebruiken tijdens een run.
class EarbudsTile extends StatefulWidget {
  const EarbudsTile({super.key});

  @override
  State<EarbudsTile> createState() => _EarbudsTileState();
}

class _EarbudsTileState extends State<EarbudsTile> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    MediaButtonService.enabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(tr('Knop op je oortjes')),
      subtitle: Text(tr('Eén keer drukken: pauze of verder. Twee keer: ronde. Speelt er muziek, dan kan die app de knop overnemen.')),
      value: _on ?? false,
      onChanged: _on == null
          ? null
          : (v) {
              setState(() => _on = v);
              MediaButtonService.setEnabled(v).ignore();
            },
    );
  }
}

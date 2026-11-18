import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/glass.dart';

/// Kaartpagina van Opnemen: de kaart vult de hele hoogte, de cijfers en knoppen liggen in matglas eroverheen.
///
/// De onderrand staat 30 hoog, zodat het paneel vrij blijft van de kaartvermelding (© Kadaster/PDOK).
class GlassMapOverlay extends StatelessWidget {
  const GlassMapOverlay({super.key, required this.map, required this.children});

  final Widget map;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(RwRadius.m),
        child: Stack(
          children: [
            Positioned.fill(child: map),
            Positioned(
              left: 10,
              right: 10,
              bottom: 30,
              child: GlassPanel(
                radius: 22,
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ],
        ),
      );
}

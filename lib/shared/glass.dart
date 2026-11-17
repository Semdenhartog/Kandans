import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Glaspaneel (PROEF, branch `glas-proef`): matglas over iets wat erachter beweegt, zoals de kaart.
///
/// Bewust alleen gebruiken waar je écht iets doorheen ziet. Valt terug op een effen vlak als
/// "minder beweging"/animaties uit staat (ook handig op tragere toestellen), want vervagen kost
/// rekenkracht en accu tijdens het opnemen.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 16,
    this.blur = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final plain = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dark = RwColors.isDark;
    final shape = BorderRadius.circular(radius);
    // Licht: zandkleurig matglas; donker: rookglas. Genoeg dekking om buiten in de zon leesbaar te blijven.
    final tint = plain
        ? RwColors.surface
        : (dark ? RwColors.background.withValues(alpha: 0.62) : RwColors.surface.withValues(alpha: 0.72));
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: shape,
        border: Border.all(
          color: dark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (plain) return panel;
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: panel,
      ),
    );
  }
}

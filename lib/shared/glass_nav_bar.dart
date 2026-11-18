import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Zwevende navigatiebalk in iOS 26-stijl: een glazen capsule met marge rondom.
///
/// Alleen de balk zelf is glas; de inhoud erboven blijft effen (leesbaar in de zon). De balk ligt níét over de
/// inhoud heen (geen `extendBody`), zodat lijsten en knoppen nooit achter de balk verdwijnen. Bij "minder
/// beweging" valt hij terug op een effen vlak, net als [GlassPanel].
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<Widget> destinations;

  @override
  Widget build(BuildContext context) {
    final plain = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dark = RwColors.isDark;
    final shape = BorderRadius.circular(36);
    final tint = plain
        ? RwColors.surface
        : (dark ? RwColors.surface.withValues(alpha: 0.62) : RwColors.surfaceHigh.withValues(alpha: 0.72));
    final bar = DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: shape,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.6)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: 80,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: selectedIndex,
        animationDuration: const Duration(milliseconds: 450),
        onDestinationSelected: onSelected,
        destinations: destinations,
      ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: plain
            ? bar
            : ClipRRect(
                borderRadius: shape,
                child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: bar),
              ),
      ),
    );
  }
}

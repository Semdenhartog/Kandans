import 'package:flutter/widgets.dart';

/// Tik je op het tabblad waar je al bent? Dan scrolt dat scherm terug naar boven.
/// De onderste balk zet hier het nummer van het tabblad in (met een teller, zodat twee keer
/// tikken ook twee keer werkt).
final tabReselected = ValueNotifier<({int tab, int seq})>((tab: -1, seq: 0));

void notifyTabReselected(int tab) => tabReselected.value = (tab: tab, seq: tabReselected.value.seq + 1);

/// Zet je om het hoofdscherm van een tabblad. Scrolt de lijst (de "primaire" scroll) naar boven.
class ScrollToTopOnReselect extends StatefulWidget {
  const ScrollToTopOnReselect({super.key, required this.tab, required this.child});
  final int tab;
  final Widget child;

  @override
  State<ScrollToTopOnReselect> createState() => _ScrollToTopOnReselectState();
}

class _ScrollToTopOnReselectState extends State<ScrollToTopOnReselect> {
  @override
  void initState() {
    super.initState();
    tabReselected.addListener(_onReselect);
  }

  @override
  void dispose() {
    tabReselected.removeListener(_onReselect);
    super.dispose();
  }

  void _onReselect() {
    if (tabReselected.value.tab != widget.tab || !mounted) return;
    final c = PrimaryScrollController.maybeOf(context);
    if (c == null) return;
    for (final p in c.positions.toList()) {
      if (p.pixels > 0) {
        p.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

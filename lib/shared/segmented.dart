import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// Keuzeschakelaar met een oranje pil die soepel naar je keuze glijdt (met een tikje).
class RwSegmented<T> extends StatelessWidget {
  const RwSegmented({super.key, required this.items, required this.selected, required this.onChanged, this.height = 46});
  final List<({T value, String label, IconData? icon})> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final index = items.indexWhere((i) => i.value == selected).clamp(0, items.length - 1);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dur = reduce ? Duration.zero : const Duration(milliseconds: 320);
    final scaled = MediaQuery.textScalerOf(context).scale(1);
    final h = height * (scaled > 1 ? scaled.clamp(1, 1.4) : 1);
    return LayoutBuilder(builder: (context, c) {
      // Binnenmaat: min de padding (2 × 4) en de rand (2 × 1).
      final w = (c.maxWidth - 10) / items.length;
      return Container(
        height: h,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: RwColors.surfaceHigh,
          borderRadius: BorderRadius.circular(h),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Stack(children: [
          AnimatedPositioned(
            duration: dur,
            curve: Curves.easeOutBack,
            left: index * w,
            top: 0,
            bottom: 0,
            width: w,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(h),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [RwColors.accentLight, RwColors.accent, RwColors.accentDeep],
                ),
                boxShadow: [BoxShadow(color: RwColors.accent.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: -2)],
              ),
            ),
          ),
          Row(children: [
            for (final (i, it) in items.indexed)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  label: it.label,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (it.value == selected) return;
                      HapticFeedback.selectionClick();
                      onChanged(it.value);
                    },
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: dur,
                        style: TextStyle(
                          fontFamily: RwFonts.body,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: i == index ? RwColors.accentDark : RwColors.muted,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (it.icon != null) ...[
                              Icon(it.icon, size: 18, color: i == index ? RwColors.accentDark : RwColors.muted),
                              const SizedBox(width: 6),
                            ],
                            Text(it.label),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      );
    });
  }
}

import 'package:flutter/material.dart';

/// Tekst waarvan elk teken dat verandert omhoog wegrolt, als een kilometerteller.
/// Met cijfers van gelijke breedte (rwTnum) blijft alles netjes op zijn plek.
class RollingText extends StatelessWidget {
  const RollingText(this.text, {super.key, required this.style, this.duration = const Duration(milliseconds: 320)});
  final String text;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) return Text(text, style: style, maxLines: 1);
    // Van rechts geteld, zodat "9:59" → "10:00" de juiste tekens laat rollen.
    final chars = text.split('');
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chars.length; i++)
            ClipRect(
              child: AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, a) {
                  final incoming = child.key == ValueKey('${chars.length - i}${chars[i]}');
                  return SlideTransition(
                    position: Tween(begin: Offset(0, incoming ? 0.6 : -0.6), end: Offset.zero).animate(a),
                    child: FadeTransition(opacity: a, child: child),
                  );
                },
                layoutBuilder: (current, previous) => Stack(alignment: Alignment.center, children: [...previous, ?current]),
                child: Text(chars[i], key: ValueKey('${chars.length - i}${chars[i]}'), style: style),
              ),
            ),
        ],
      ),
    );
  }
}

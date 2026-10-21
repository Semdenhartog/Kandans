import 'package:flutter/material.dart';

/// Tekst met een zacht metalen verloop, waar af en toe een lichtglans overheen trekt.
class ShineText extends StatefulWidget {
  const ShineText(this.text, {super.key, required this.style, this.colors = const [Color(0xFFFFFFFF), Color(0xFFFFE6CF), Color(0xFFE9D3BE)]});
  final String text;
  final TextStyle style;
  final List<Color> colors;

  @override
  State<ShineText> createState() => _ShineTextState();
}

class _ShineTextState extends State<ShineText> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 6500));

  @override
  void initState() {
    super.initState();
    if (!WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      _c.value = 0.55; // eerste glans kort na openen
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          // Glans alleen in het laatste kwart van de cyclus.
          final t = ((_c.value - 0.75) / 0.25).clamp(0.0, 1.0);
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) {
              final base = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: widget.colors,
              );
              if (t <= 0 || t >= 1) return base.createShader(r);
              final x = -0.4 + 1.8 * t;
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [widget.colors.last, widget.colors.first, Colors.white, widget.colors.first, widget.colors.last],
                stops: [0, (x - 0.15).clamp(0.0, 1.0), x.clamp(0.0, 1.0), (x + 0.15).clamp(0.0, 1.0), 1],
              ).createShader(r);
            },
            child: child,
          );
        },
        child: Text(widget.text, style: widget.style.copyWith(color: Colors.white)),
      );
}

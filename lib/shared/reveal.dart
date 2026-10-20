import 'package:flutter/material.dart';

/// Laat een grafiek zich van links naar rechts intekenen (eenmalig, bij verschijnen).
/// Werkt om elke CustomPaint heen, zonder dat de painter iets hoeft te weten.
class RevealIn extends StatelessWidget {
  const RevealIn({super.key, required this.child, this.duration = const Duration(milliseconds: 1100)});
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, t, c) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => LinearGradient(
          colors: const [Colors.white, Colors.white, Colors.transparent],
          stops: [0, (t * 1.08 - 0.08).clamp(0.0, 1.0), (t * 1.08).clamp(0.0, 1.0)],
        ).createShader(r),
        child: c,
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../data/services/sound_service.dart';

/// Een korte regen van confetti in RunWise-kleuren (bij een record of nieuwe badge). Eén keer, ~2,5 s.
class Confetti extends StatefulWidget {
  const Confetti({super.key, this.count = 90});
  final int count;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _Bit {
  _Bit(math.Random r)
      : x = r.nextDouble(),
        delay = r.nextDouble() * 0.35,
        speed = 0.6 + r.nextDouble() * 0.7,
        drift = (r.nextDouble() - 0.5) * 0.35,
        spin = (r.nextDouble() - 0.5) * 14,
        size = 5 + r.nextDouble() * 7,
        color = const [RwColors.accent, RwColors.accentDeep, RwColors.accentLight, RwColors.text, RwColors.good][r.nextInt(5)],
        round = r.nextBool();
  final double x, delay, speed, drift, spin, size;
  final Color color;
  final bool round;
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final _bits = List.generate(widget.count, (_) => _Bit(math.Random()));
  bool _off = false;

  @override
  void initState() {
    super.initState();
    _off = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (!_off) {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        HapticFeedback.heavyImpact();
        SoundService.instance.play(RwSound.record).ignore();
        _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_off) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => _c.value == 0 || _c.isCompleted
          ? const SizedBox.shrink()
          : CustomPaint(painter: _ConfettiPainter(_bits, _c.value), size: Size.infinite),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);
  final List<_Bit> bits;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bits) {
      final local = ((t - b.delay) / (1 - b.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + local * b.speed * (size.height + 60);
      final x = (b.x + b.drift * local + 0.02 * math.sin(local * 12 + b.x * 6)) * size.width;
      final fade = local > 0.8 ? (1 - local) / 0.2 : 1.0;
      final p = Paint()..color = b.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin * local);
      if (b.round) {
        canvas.drawCircle(Offset.zero, b.size / 2.4, p);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.45), const Radius.circular(1.5)), p);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

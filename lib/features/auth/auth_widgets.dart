import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/aura.dart';
import '../../shared/route_backdrop.dart';
import '../../core/appearance.dart';

/// Gemeenschappelijke opmaak voor login, registratie en activatie.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: RwAura()),
        const Positioned.fill(child: DrawnRoute(top: true)),
        SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _GlowLogo(),
                  const SizedBox(height: 40),
                  Text(
                    eyebrow.toUpperCase(),
                    style: TextStyle(
                      color: RwColors.accent,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 32,
                      fontFamily: RwFonts.display, fontFeatures: rwTnum,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(subtitle, style: TextStyle(color: RwColors.muted, height: 1.5)),
                  const SizedBox(height: 28),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
      ]),
    );
  }
}

/// Logo dat bij openen zacht invaagt, met een lichtkrans erachter.
class _GlowLogo extends StatelessWidget {
  const _GlowLogo();

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
        ),
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
          Positioned(
            left: -50,
            top: -50,
            child: IgnorePointer(
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [RwColors.accent.withValues(alpha: 0.28), RwColors.accent.withValues(alpha: 0)]),
                ),
              ),
            ),
          ),
          const RunWiseLogo(height: 38),
        ]),
      );
}

class RunWiseLogo extends StatelessWidget {
  const RunWiseLogo({super.key, this.height = 30});

  /// Hoogte van het merkteken; het woordmerk schaalt mee.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kadans',
      image: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          kadansImage('assets/logo/mark.png', height: height),
          SizedBox(width: height * 0.35),
          kadansImage('assets/logo/wordmark.png', height: height * 0.46),
        ],
      ),
    );
  }
}

class FormError extends StatelessWidget {
  const FormError(this.message, {super.key});
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(message!, style: TextStyle(color: RwColors.danger)),
    );
  }
}

class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: RwColors.accentDark),
            )
          : Text(label),
    );
  }
}

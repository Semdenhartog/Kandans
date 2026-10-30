import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/aura.dart';
import '../../shared/route_backdrop.dart';
import '../../core/appearance.dart';
import '../../core/i18n.dart';
import '../../shared/language_picker.dart';

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
        Positioned.fill(child: RwAura()),
        Positioned.fill(child: DrawnRoute(top: true)),
        // Taal kiezen, meteen op het beginscherm.
        const SafeArea(child: Align(alignment: Alignment.topRight, child: Padding(padding: EdgeInsets.all(8), child: LanguageButton()))),
        SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _GlowLogo(),
                  SizedBox(height: 40),
                  Text(
                    tr(eyebrow).toUpperCase(),
                    style: TextStyle(
                      color: RwColors.accent,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    tr(title),
                    style: TextStyle(
                      fontSize: 32,
                      fontFamily: RwFonts.display, fontFeatures: rwTnum,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(tr(subtitle), style: TextStyle(color: RwColors.muted, height: 1.5)),
                  SizedBox(height: 28),
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
        duration: Duration(milliseconds: 900),
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
          RunWiseLogo(height: 38),
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
      label: tr('Kadans'),
      image: true,
      child: kadansLockup(height: height * 1.15),
    );
  }
}

class FormError extends StatelessWidget {
  const FormError(this.message, {super.key});
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

/// Laatst gekozen hoofdtabblad (Vandaag, Routes, Logboek, Samen), zodat "terug" vanuit Ik of Coach
/// weer op dat tabblad uitkomt.
int lastMainBranch = 0;

/// Ik: rechtsboven op elk hoofdtabblad. Eén vaste plek voor profiel, instellingen en account.
class MeButton extends StatelessWidget {
  const MeButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tr('Ik'),
        icon: Icon(Icons.account_circle_outlined, color: RwColors.muted),
        onPressed: () => context.go('/me'),
      );
}

/// Vraag de coach: staat waar de vraag ontstaat (Vandaag, Logboek, een run), in plaats van als los tabblad.
class CoachButton extends StatelessWidget {
  const CoachButton({super.key, this.compact = true});
  final bool compact;

  @override
  Widget build(BuildContext context) => compact
      ? IconButton(
          tooltip: tr('Vraag de coach'),
          icon: Icon(Icons.auto_awesome_outlined, color: RwColors.accent),
          onPressed: () => context.go('/coach'),
        )
      : OutlinedButton.icon(
          onPressed: () => context.go('/coach'),
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: Text(tr('Vraag de coach')),
        );
}

/// Terug-knop voor Ik en Coach: die zitten niet meer in de balk onderin.
class BackToTabButton extends StatelessWidget {
  const BackToTabButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tr('Terug'),
        icon: const Icon(Icons.arrow_back),
        onPressed: () => goBackToTab(context),
      );
}

void goBackToTab(BuildContext context) {
  try {
    StatefulNavigationShell.of(context).goBranch(lastMainBranch);
  } catch (_) {
    context.go('/today');
  }
}

/// Om Ik of Coach heen: de terugknop van de telefoon gaat naar het laatste tabblad in plaats van de app te sluiten.
class BackToTabScope extends StatelessWidget {
  const BackToTabScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) goBackToTab(context);
        },
        child: child,
      );
}

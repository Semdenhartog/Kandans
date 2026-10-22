import 'package:flutter/material.dart';

import 'widgets.dart';

/// Vraagt het even voordat je een half ingevuld scherm verlaat (terugknop of terugvegen).
class DiscardGuard extends StatelessWidget {
  const DiscardGuard({
    super.key,
    required this.dirty,
    required this.child,
    this.message = 'Wat je hebt ingevuld wordt niet bewaard.',
  });

  /// Is er iets ingevuld dat nog niet is opgeslagen? (Wordt pas bekeken als je weggaat.)
  final bool Function() dirty;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!dirty()) {
          Navigator.of(context).pop();
          return;
        }
        final leave = await confirmDialog(
          context,
          title: 'Weggaan zonder opslaan?',
          message: message,
          confirmLabel: 'Weggooien',
        );
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: child,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

/// Kies je taal (blad onderin). Daarna tekent de hele app zich opnieuw in de nieuwe taal.
Future<void> showLanguagePicker(BuildContext context) async {
  final current = LanguageController.instance.lang;
  final picked = await showModalBottomSheet<AppLanguage>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(tr('Taal'), style: RwText.title.copyWith(fontSize: 20)),
        ),
        for (final l in AppLanguage.values)
          ListTile(
            leading: Icon(l == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: l == current ? RwColors.accent : RwColors.subtle),
            title: Text(l.label),
            subtitle: l == AppLanguage.nl ? null : Text(_beta[l]!, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, l),
          ),
      ]),
    ),
  );
  if (picked == null || picked == current) return;
  HapticFeedback.selectionClick();
  await LanguageController.instance.set(picked);
}

/// Eerlijk: nog niet alles is vertaald.
const _beta = {
  AppLanguage.en: 'Beta: some screens are still in Dutch',
  AppLanguage.de: 'Beta: einige Bildschirme sind noch auf Niederländisch',
  AppLanguage.fr: 'Bêta : certains écrans sont encore en néerlandais',
  AppLanguage.es: 'Beta: algunas pantallas siguen en neerlandés',
};

/// Knopje met wereldbol en taalcode (bijv. rechtsboven op het beginscherm).
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: LanguageController.instance,
        builder: (context, _) => TextButton.icon(
          onPressed: () => showLanguagePicker(context),
          icon: const Icon(Icons.language, size: 18),
          label: Text(LanguageController.instance.lang.code.toUpperCase()),
          style: TextButton.styleFrom(foregroundColor: RwColors.muted),
        ),
      );
}

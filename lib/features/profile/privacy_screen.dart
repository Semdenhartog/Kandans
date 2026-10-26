import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import 'privacy_text.dart';

/// Opent de privacyverklaring in de app (werkt ook zonder internet of als de website even niet bereikbaar is).
void openPrivacy(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()));
}

/// "**vet** rest" → tekst met vette stukken.
List<TextSpan> _rich(String s, TextStyle base) {
  final parts = s.split('**');
  return [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].isNotEmpty)
        TextSpan(text: parts[i], style: i.isOdd ? base.copyWith(fontWeight: FontWeight.w700, color: RwColors.text) : base),
  ];
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(color: RwColors.muted, height: 1.5, fontSize: 15);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacyverklaring'),
        actions: [
          IconButton(
            tooltip: 'Open op de website',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(Uri.parse(AppConfig.privacyUrl), mode: LaunchMode.externalApplication).catchError((_) => false),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          itemCount: privacyBlocks.length,
          itemBuilder: (context, i) {
            final b = privacyBlocks[i];
            switch (b.kind) {
              case 'h':
                return Padding(
                  padding: const EdgeInsets.only(top: 22, bottom: 6),
                  child: Text(b.text, style: RwText.title.copyWith(fontSize: 20)),
                );
              case 'meta':
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(b.text, style: TextStyle(color: RwColors.subtle, fontSize: 13)),
                );
              case 'li':
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 9, right: 10),
                      child: Container(width: 5, height: 5, decoration: BoxDecoration(color: RwColors.accent, shape: BoxShape.circle)),
                    ),
                    Expanded(child: Text.rich(TextSpan(children: _rich(b.text, body)))),
                  ]),
                );
              case 'row':
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: RwColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: RwColors.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.text, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)),
                    const SizedBox(height: 4),
                    Text.rich(TextSpan(children: _rich(b.detail ?? '', body.copyWith(fontSize: 14)))),
                  ]),
                );
              default:
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text.rich(TextSpan(children: _rich(b.text, body))),
                );
            }
          },
        ),
      ),
    );
  }
}

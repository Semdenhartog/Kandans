import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Wordt getoond als de app zonder Supabase-instellingen is gestart.
class ConfigMissingApp extends StatelessWidget {
  const ConfigMissingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kadans is nog niet ingesteld',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, fontFamily: RwFonts.display, fontFeatures: rwTnum),
                ),
                SizedBox(height: 12),
                Text(
                  'Start de app met je Supabase-gegevens:\n\n'
                  'flutter run --dart-define-from-file=config.json\n\n'
                  'Kijk in README.md hoe je config.json maakt.',
                  style: TextStyle(color: RwColors.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

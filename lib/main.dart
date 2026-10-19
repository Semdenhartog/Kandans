import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/error_reporter.dart';
import 'core/theme.dart';
import 'data/services/notification_service.dart';
import 'shared/config_missing_app.dart';
import 'data/services/app_lock_service.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // Onverwachte fouten melden in Supabase (alleen als je bent ingelogd).
    ErrorReporter.install();
    // Licenties van de meegeleverde lettertypes (SIL Open Font License).
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(['Saira'], await rootBundle.loadString('assets/fonts/OFL-Saira.txt'));
      yield LicenseEntryWithLineBreaks(['DM Sans'], await rootBundle.loadString('assets/fonts/OFL-DMSans.txt'));
    });

    // Toon fouten in schermen als leesbare tekst (in plaats van een leeg/grijs scherm).
    ErrorWidget.builder = (details) => _ErrorText(details.exceptionAsString());

    if (!AppConfig.isConfigured) {
      runApp(const ConfigMissingApp());
      return;
    }
    // Eerst direct iets tonen, daarna pas opstarten.
    runApp(const _Bootstrap());
  }, (error, stack) {
    debugPrint('Onverwachte fout: $error\n$stack');
    ErrorReporter.report(error, stack, context: 'zone');
  });
}

/// Start Supabase en de datumnotatie, en toont een foutmelding als dat mislukt.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<void> _init = _start();

  Future<void> _start() async {
    await initializeDateFormatting('nl_NL');
    await NotificationService.instance.init().catchError((_) {});
    await AppLockService.instance.load();
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    ).timeout(const Duration(seconds: 20));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done && !snap.hasError) {
          return const ProviderScope(child: RunWiseApp());
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: snap.hasError
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: RwColors.danger, size: 48),
                            const SizedBox(height: 12),
                            const Text('RunWise kon niet starten',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            SelectableText('${snap.error}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: RwColors.muted)),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: () => setState(() => _init = _start()),
                              child: const Text('Opnieuw proberen'),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/logo/logo.png', width: 220, semanticLabel: 'RunWise'),
                            const SizedBox(height: 28),
                            const CircularProgressIndicator(),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RwColors.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Fout: $message',
          textDirection: TextDirection.ltr,
          style: const TextStyle(color: RwColors.danger, fontSize: 13),
        ),
      ),
    );
  }
}

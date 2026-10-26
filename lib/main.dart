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
import 'data/services/heart_rate_service.dart';
import 'core/appearance.dart';
import 'domain/run_goal.dart';

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
    await AppearanceController.instance.load();
    await loadRunGoal();
    await initializeDateFormatting('nl_NL');
    await NotificationService.instance.init().catchError((_) {});
    await AppLockService.instance.load();
    await HeartRateService.instance.load();
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    ).timeout(const Duration(seconds: 20));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snap) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 550),
        switchInCurve: Curves.easeOut,
        child: _screen(context, snap),
      ),
    );
  }

  Widget _screen(BuildContext context, AsyncSnapshot<void> snap) {
        if (snap.connectionState == ConnectionState.done && !snap.hasError) {
          return const ProviderScope(key: ValueKey('app'), child: RunWiseApp());
        }
        return MaterialApp(
          key: const ValueKey('start'),
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
                            Icon(Icons.error_outline, color: RwColors.danger, size: 48),
                            const SizedBox(height: 12),
                            const Text('Kadans kon niet starten',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            SelectableText('${snap.error}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: RwColors.muted)),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: () => setState(() => _init = _start()),
                              child: const Text('Opnieuw proberen'),
                            ),
                          ],
                        )
                      : const _Intro(),
                ),
              ),
            ),
          ),
        );
  }
}

/// Opstartscherm: logo dat zacht binnenkomt over een ademende gloed, met een dunne laadlijn.
class _Intro extends StatefulWidget {
  const _Intro();

  @override
  State<_Intro> createState() => _IntroState();
}

class _IntroState extends State<_Intro> with TickerProviderStateMixin {
  late final _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  late final _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);

  @override
  void dispose() {
    _in.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appear = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 300,
          height: 220,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedBuilder(
              animation: _glow,
              builder: (_, _) => Container(
                width: 220 + 40 * _glow.value,
                height: 220 + 40 * _glow.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    RwColors.accent.withValues(alpha: 0.16 + 0.08 * _glow.value),
                    RwColors.accent.withValues(alpha: 0),
                  ]),
                ),
              ),
            ),
            FadeTransition(
              opacity: appear,
              child: ScaleTransition(
                scale: Tween(begin: 0.92, end: 1.0).animate(appear),
                child: kadansImage('assets/logo/logo.png', width: 220, semanticLabel: 'Kadans'),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        FadeTransition(
          opacity: appear,
          child: SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(2)),
              child: LinearProgressIndicator(minHeight: 2, color: RwColors.accent, backgroundColor: RwColors.bar),
            ),
          ),
        ),
      ],
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
          style: TextStyle(color: RwColors.danger, fontSize: 13),
        ),
      ),
    );
  }
}

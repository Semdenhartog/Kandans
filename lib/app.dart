import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/appearance.dart';
import 'core/i18n.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/lock/app_lock_gate.dart';

class RunWiseApp extends ConsumerStatefulWidget {
  const RunWiseApp({super.key});

  @override
  ConsumerState<RunWiseApp> createState() => _RunWiseAppState();
}

class _RunWiseAppState extends ConsumerState<RunWiseApp> with WidgetsBindingObserver {
  final _appearance = AppearanceController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appearance.addListener(_changed);
    LanguageController.instance.addListener(_changed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appearance.removeListener(_changed);
    LanguageController.instance.removeListener(_changed);
    super.dispose();
  }

  // Telefoon wisselt tussen licht en donker (bijv. 's avonds automatisch).
  @override
  void didChangePlatformBrightness() => _changed();

  void _changed() {
    if (!mounted) return;
    _appearance.apply(View.of(context).platformDispatcher.platformBrightness);
    setState(() {});
    // Schermen lezen de kleuren direct; laat ze allemaal opnieuw tekenen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) rebuildAllChildren(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    _appearance.apply(View.of(context).platformDispatcher.platformBrightness);
    return MaterialApp.router(
      title: 'Kadans',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
      // Grote letters (instelling van de telefoon) volgen, maar niet zo groot
      // dat de kaarten en grote getallen uit beeld vallen (tot 160%; getest in screens.yml).
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.6)),
          child: AppLockGate(child: child ?? const SizedBox.shrink()),
        );
      },
      locale: LanguageController.instance.lang.locale,
      supportedLocales: [for (final l in AppLanguage.values) l.locale],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

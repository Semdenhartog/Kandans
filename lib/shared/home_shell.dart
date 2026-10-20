import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import 'aura.dart';
import '../data/services/location_service.dart';
import '../data/services/offline_cache.dart';
import '../data/services/sync_service.dart';
import '../features/lock/app_lock_gate.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../core/format.dart';
import '../data/services/recording_store.dart';
import '../data/services/run_recorder_service.dart';
import '../features/record/record_run_screen.dart';

/// Onderste navigatiebalk met de vijf hoofdtabbladen.
/// Haalt bij het openen (en terugkomen in) de app automatisch nieuwe runs op
/// uit gekoppelde bronnen (horloge via Health Connect, Strava).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSync();
      _onboarding();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoSync();
  }

  Future<void> _onboarding() async {
    final next = await showOnboardingIfNeeded(context);
    if (mounted) await _offerRestore();
    if (mounted) await maybeOfferFingerprint(context);
    if (next == null || !mounted) return;
    // Na de rondleiding kan er locatie zijn: weer opnieuw ophalen.
    ref.invalidate(weatherLocationProvider);
    switch (next) {
      case OnboardingNext.connect:
        context.go('/me');
      case OnboardingNext.route:
        context.go('/routes/maken');
      case OnboardingNext.today:
        context.go('/today');
    }
  }

  /// Was er een run bezig toen de app werd afgesloten? Dan kun je hem afmaken of opslaan.
  Future<void> _offerRestore() async {
    final svc = RunRecorderService.instance;
    if (svc.isRecording) return;
    final r = await RecordingStore.load();
    if (r == null || !mounted) return;
    final when = r.startedAt == null ? '' : ' van ${Fmt.time(r.startedAt!)}';
    final what = r.indoor ? Fmt.duration(r.movingSeconds) : '${Fmt.km(r.distance, decimals: 2)} in ${Fmt.duration(r.movingSeconds)}';
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.restore, size: 36),
        title: const Text('Je run is onderbroken'),
        content: Text('Je run$when is gestopt doordat de app werd afgesloten ($what). '
            'Je kunt verder lopen of hem opslaan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Weggooien')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verder of opslaan')),
        ],
      ),
    );
    if (choice == true) {
      await svc.restore(r);
      if (mounted) openRecorder(context);
    } else if (choice == false) {
      await RecordingStore.clear();
    }
  }

  void _autoSync() {
    // Stil op de achtergrond; fouten zie je pas als je zelf vernieuwt.
    ref.read(syncServiceProvider).syncAll().ignore();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    return Scaffold(
      // Aura achter de tabbladen; de tabbladen zelf zijn doorzichtig.
      body: Stack(children: [const Positioned.fill(child: RwAura()), shell]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _OfflineBanner(),
          // Satijnen navigatiebalk: licht doorschijnend, met een fijne lichte rand bovenaan.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [RwColors.surfaceHigh.withValues(alpha: 0.92), RwColors.surface],
              ),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
            ),
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              selectedIndex: shell.currentIndex,
              animationDuration: const Duration(milliseconds: 450),
              onDestinationSelected: (i) {
                if (i != shell.currentIndex) HapticFeedback.selectionClick();
                shell.goBranch(i, initialLocation: i == shell.currentIndex);
              },
              destinations: const [
                NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny), label: 'Vandaag'),
                NavigationDestination(icon: Icon(Icons.directions_run_outlined), selectedIcon: Icon(Icons.directions_run), label: 'Runs'),
                NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Routes'),
                NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Coach'),
                NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Ik'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Smalle balk als de app geen internet heeft en bewaarde gegevens toont.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: OfflineCache.showingCachedSince,
      builder: (context, since, _) {
        if (since == null) return const SizedBox.shrink();
        final t = since.toLocal();
        final hhmm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        final today = DateUtils.isSameDay(t, DateTime.now());
        return Semantics(
          liveRegion: true,
          child: Container(
            width: double.infinity,
            color: RwColors.surfaceHigh,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.cloud_off, size: 16, color: RwColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Geen internet. Je ziet de gegevens van ${today ? 'vandaag $hhmm' : '${t.day}-${t.month} $hhmm'}.',
                    style: const TextStyle(fontSize: 13, color: RwColors.muted),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

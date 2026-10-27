import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_actions/quick_actions.dart';

import '../core/theme.dart';
import 'tab_scroll.dart';
import 'aura.dart';
import 'whats_new.dart';
import '../data/services/location_service.dart';
import '../data/services/offline_cache.dart';
import '../data/services/pending_runs.dart';
import '../data/services/sync_service.dart';
import '../features/lock/app_lock_gate.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../core/format.dart';
import '../data/services/recording_store.dart';
import '../data/services/run_recorder_service.dart';
import '../features/record/record_run_screen.dart';
import '../core/i18n.dart';

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
      PendingRunStore.refreshCount().ignore();
      _autoSync();
      _onboarding();
      _setupShortcuts();
    });
  }

  /// Lang drukken op het app-icoon: Start run, Loopband, Beste moment.
  void _setupShortcuts() {
    try {
      const qa = QuickActions();
      qa.initialize((type) {
        if (!mounted) return;
        if (RunRecorderService.instance.isRecording) {
          openRecorder(context);
          return;
        }
        switch (type) {
          case 'run':
            openRecorder(context);
          case 'treadmill':
            openRecorder(context, indoor: true);
          case 'best':
            context.go('/today');
        }
      });
      qa.setShortcutItems([
        ShortcutItem(type: 'run', localizedTitle: 'Start run'),
        ShortcutItem(type: 'treadmill', localizedTitle: 'Loopband'),
        ShortcutItem(type: 'best', localizedTitle: 'Beste moment'),
      ]).ignore();
    } catch (_) {
      // Snelkoppelingen zijn een extraatje.
    }
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
    if (mounted) await showWhatsNewIfNeeded(context, skip: next != null);
    if (next == null || !mounted) return;
    // Na de rondleiding kan er locatie zijn: weer opnieuw ophalen.
    ref.invalidate(weatherLocationProvider);
    switch (next) {
      case OnboardingNext.connect:
        context.go('/me');
      case OnboardingNext.route:
        context.go('/routes/maken');
      case OnboardingNext.race:
        context.go('/me/races/new');
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
        icon: Icon(Icons.restore, size: 36),
        title: Text(tr('Je run is onderbroken')),
        content: Text('Je run$when is gestopt doordat de app werd afgesloten ($what). '
            'Je kunt verder lopen of hem opslaan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Weggooien'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Verder of opslaan'))),
        ],
      ),
    );
    if (choice == true) {
      await svc.restore(r);
      if (mounted) openRecorder(context);
    } else if (choice == false) {
      // Eerst 8 seconden de kans om het terug te draaien; pas daarna echt wissen.
      if (!mounted) return;
      var undo = false;
      final bar = ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Run weggegooid.')),
        duration: Duration(seconds: 8),
        action: SnackBarAction(label: tr('Toch bewaren'), onPressed: () => undo = true),
      ));
      await bar.closed;
      if (undo) {
        await svc.restore(r);
        if (mounted) openRecorder(context);
      } else {
        await RecordingStore.clear();
      }
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
      body: Stack(children: [Positioned.fill(child: RwAura()), shell]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _OfflineBanner(),
          const PendingRunsBanner(),
          // Satijnen navigatiebalk: licht doorschijnend, met een fijne lichte rand bovenaan.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [RwColors.surfaceHigh.withValues(alpha: 0.92), RwColors.surface],
              ),
              border: Border(top: BorderSide(color: RwColors.hairline)),
            ),
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              // Zes tabbladen: alleen het gekozen tabblad met naam, anders wordt het te krap.
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              selectedIndex: shell.currentIndex,
              animationDuration: Duration(milliseconds: 450),
              onDestinationSelected: (i) {
                if (i != shell.currentIndex) HapticFeedback.selectionClick();
                if (i == shell.currentIndex) notifyTabReselected(i);
                shell.goBranch(i, initialLocation: i == shell.currentIndex);
              },
              destinations: homeDestinations(),
            ),
          ),
        ],
      ),
    );
  }
}

/// De zes tabbladen onderin (ook gebruikt voor de schermafbeelding van de balk).
List<NavigationDestination> homeDestinations() => [
  NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny), label: tr('Vandaag')),
  NavigationDestination(icon: Icon(Icons.directions_run_outlined), selectedIcon: Icon(Icons.directions_run), label: tr('Runs')),
  NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: tr('Routes')),
  NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: tr('Coach')),
  NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum), label: tr('Forum')),
  NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: tr('Ik')),
    ];

/// Smalle balk als de app geen internet heeft en bewaarde gegevens toont.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: OfflineCache.showingCachedSince,
      builder: (context, since, _) {
        if (since == null) return SizedBox.shrink();
        final t = since.toLocal();
        final hhmm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        final today = DateUtils.isSameDay(t, DateTime.now());
        return Semantics(
          liveRegion: true,
          child: Container(
            width: double.infinity,
            color: RwColors.surfaceHigh,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.cloud_off, size: 16, color: RwColors.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Geen internet. Je ziet de gegevens van ${today ? 'vandaag $hhmm' : '${t.day}-${t.month} $hhmm'}.',
                    style: TextStyle(fontSize: 13, color: RwColors.muted),
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

/// Smalle balk zolang er opgenomen runs op de telefoon wachten op internet.
class PendingRunsBanner extends ConsumerWidget {
  const PendingRunsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<int>(
      valueListenable: PendingRunStore.count,
      builder: (context, n, _) {
        if (n <= 0) return SizedBox.shrink();
        return Semantics(
          liveRegion: true,
          button: true,
          label: n == 1 ? '1 run wacht op internet. Tik om opnieuw te proberen.' : '$n runs wachten op internet. Tik om opnieuw te proberen.',
          child: InkWell(
            onTap: () async {
              HapticFeedback.selectionClick();
              final sent = await ref.read(syncServiceProvider).flushPendingRuns().catchError((Object _) => 0);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(sent > 0
                    ? (sent == 1 ? 'Je run is opgeslagen.' : '$sent runs opgeslagen.')
                    : 'Nog geen verbinding. We proberen het vanzelf opnieuw.'),
              ));
            },
            child: Container(
              width: double.infinity,
              color: RwColors.surfaceHigh,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 16, color: RwColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      n == 1 ? '1 run wacht op internet' : '$n runs wachten op internet',
                      style: TextStyle(fontSize: 13, color: RwColors.muted),
                    ),
                  ),
                  Text(tr('Opnieuw'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: RwColors.accent)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/services/app_lock_service.dart';
import '../../data/services/run_recorder_service.dart';

/// Legt een slot over de app zolang je je vingerafdruk nog niet hebt gegeven.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  final _lock = AppLockService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lock.locked.addListener(_maybeAsk);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lock.locked.removeListener(_maybeAsk);
    super.dispose();
  }

  bool get _loggedIn {
    try {
      return ref.read(supabaseProvider).auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  void _maybeAsk() {
    if (_lock.locked.value && _loggedIn && mounted) _lock.unlock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _lock.onPaused();
    if (state == AppLifecycleState.resumed) _lock.onResumed(recording: RunRecorderService.instance.isRecording);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _lock.locked,
      builder: (context, locked, child) {
        final show = locked && _loggedIn;
        return Stack(
          children: [
            // Achter het slot niets laten zien of aanklikken.
            Offstage(offstage: show, child: TickerMode(enabled: !show, child: child!)),
            if (show) const _LockScreen(),
          ],
        );
      },
      child: widget.child,
    );
  }
}

class _LockScreen extends ConsumerWidget {
  const _LockScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = AppLockService.instance;
    return Material(
      color: RwColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(),
              Icon(Icons.fingerprint, size: 88, color: RwColors.accent),
              const SizedBox(height: 20),
              const Text('Kadans is vergrendeld',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Gebruik je vingerafdruk, of de pincode van je telefoon.',
                  textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted)),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: lock.unlock,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Ontgrendelen'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  lock.reset();
                  await ref.read(supabaseProvider).auth.signOut();
                },
                child: Text('Uitloggen en opnieuw inloggen met wachtwoord', style: TextStyle(color: RwColors.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Na inloggen met je wachtwoord: één keer vragen of je voortaan je vingerafdruk wilt gebruiken.
Future<void> maybeOfferFingerprint(BuildContext context) async {
  final lock = AppLockService.instance;
  if (!lock.offerAfterLogin || lock.enabled.value) return;
  lock.offerAfterLogin = false;
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('fingerprint_offered') ?? false) return;
    if (!await lock.isAvailable() || !context.mounted) return;
    await p.setBool('fingerprint_offered', true);
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.fingerprint, size: 40, color: RwColors.accent),
      title: const Text('Voortaan met je vingerafdruk?'),
      content: const Text('Je blijft ingelogd. Bij het openen van Kadans ontgrendel je de app met je vingerafdruk '
          '(of de pincode van je telefoon). Je kunt dit altijd uitzetten bij Ik.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nee, bedankt')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ja, aanzetten')),
      ],
    ),
  );
  if (yes == true) await lock.setEnabled(true);
}

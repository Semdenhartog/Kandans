import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/sync_service.dart';
import '../../shared/widgets.dart';

/// Strava-oranje (huisstijl van Strava voor de "Koppel met Strava"-knop).
const _stravaOrange = Color(0xFFFC5200);

/// Kaart in het tabblad Ik: horloge (Health Connect) en Strava koppelen.
class ConnectionsCard extends ConsumerStatefulWidget {
  const ConnectionsCard({super.key});

  @override
  ConsumerState<ConnectionsCard> createState() => _ConnectionsCardState();
}

class _ConnectionsCardState extends ConsumerState<ConnectionsCard> with WidgetsBindingObserver {
  Future<bool>? _writeOn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Terug in de app (bijv. na Strava of Health Connect): status opnieuw ophalen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(stravaConnectionProvider);
      ref.invalidate(healthStatusProvider);
    }
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final msg = await action();
      if (mounted && msg != null) showMessage(context, msg);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  SyncService get _sync => ref.read(syncServiceProvider);

  String _runs(int n) => n == 0 ? 'Geen nieuwe runs gevonden.' : '$n nieuwe run${n == 1 ? '' : 's'} opgehaald.';

  Future<void> _healthTap(HealthStatus status) => _run(() async {
        switch (status) {
          case HealthStatus.needsInstall:
            await _sync.installHealthConnect();
            return 'Installeer Health Connect en kom daarna terug naar RunWise.';
          case HealthStatus.notConnected:
            final ok = await _sync.connectHealth();
            ref.invalidate(healthStatusProvider);
            if (!ok) return 'Geen toestemming gegeven. Je kunt het later opnieuw proberen.';
            final n = await _sync.syncHealth();
            ref.invalidate(activitiesProvider);
            return 'Gekoppeld! ${_runs(n)}';
          case HealthStatus.connected:
            final n = await _sync.syncHealth();
            ref.invalidate(activitiesProvider);
            return _runs(n);
          case HealthStatus.unavailable:
            return 'Health Connect is niet beschikbaar op dit toestel.';
        }
      });

  Future<void> _stravaTap(StravaConnection? conn) async {
    if (conn == null) {
      await _run(() async {
        await _sync.connectStrava();
        return null;
      });
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: RwColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Nu runs ophalen'),
              onTap: () => Navigator.pop(ctx, 'sync'),
            ),
            ListTile(
              leading: const Icon(Icons.link_off, color: RwColors.danger),
              title: const Text('Strava ontkoppelen', style: TextStyle(color: RwColors.danger)),
              onTap: () => Navigator.pop(ctx, 'disconnect'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'sync') {
      await _run(() async {
        final n = await _sync.syncStrava();
        ref.invalidate(activitiesProvider);
        ref.invalidate(stravaConnectionProvider);
        return _runs(n);
      });
    } else {
      final ok = await confirmDialog(
        context,
        title: 'Strava ontkoppelen?',
        message: 'RunWise haalt dan geen runs meer op uit Strava, en de runs die uit Strava kwamen worden uit RunWise verwijderd. '
            'In Strava zelf verandert er niets.',
        confirmLabel: 'Ontkoppelen',
      );
      if (!ok) return;
      await _run(() async {
        await _sync.disconnectStrava();
        ref.invalidate(stravaConnectionProvider);
        ref.invalidate(activitiesProvider);
        return 'Strava is ontkoppeld.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(healthStatusProvider).value ?? HealthStatus.unavailable;
    final strava = ref.watch(stravaConnectionProvider);
    final conn = strava.value;

    final healthSubtitle = switch (health) {
      HealthStatus.connected => 'Gekoppeld: runs van je horloge komen automatisch binnen',
      HealthStatus.notConnected => 'Fitbit, Samsung, Garmin, Polar en meer via Health Connect',
      HealthStatus.needsInstall => 'Installeer eerst de app Health Connect',
      HealthStatus.unavailable => 'Niet beschikbaar op dit toestel',
    };

    final stravaSubtitle = conn == null
        ? 'Runs automatisch ophalen uit Strava'
        : conn.lastError ??
            'Gekoppeld${conn.athleteName == null ? '' : ' als ${conn.athleteName}'}'
                '${conn.lastSyncedAt == null ? '' : ' · bijgewerkt ${Fmt.date(conn.lastSyncedAt!)}'}';

    return RwCard(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.watch_outlined,
              color: health == HealthStatus.connected ? RwColors.accent : RwColors.subtle,
            ),
            title: Text(health == HealthStatus.connected ? 'Horloge' : 'Koppel je horloge'),
            subtitle: Text(healthSubtitle),
            trailing: health == HealthStatus.connected ? const Icon(Icons.sync, color: RwColors.subtle) : null,
            enabled: !_busy && health != HealthStatus.unavailable,
            onTap: () => _healthTap(health),
          ),
          if (health != HealthStatus.unavailable && health != HealthStatus.needsInstall)
            FutureBuilder<bool>(
              future: _writeOn ??= _sync.healthWriteEnabled(),
              builder: (context, snap) => SwitchListTile(
                secondary: const Icon(Icons.upload_outlined, color: RwColors.subtle),
                title: const Text('Opgenomen runs naar Samsung Health'),
                subtitle: const Text('Zet runs die je in RunWise opneemt ook in Health Connect (Samsung Health, Google Fit)'),
                value: snap.data ?? false,
                onChanged: _busy
                    ? null
                    : (v) async {
                        final ok = await _sync.setHealthWrite(v);
                        if (!ok && mounted) showMessage(context, 'Geen toestemming gekregen van Health Connect.');
                        setState(() => _writeOn = _sync.healthWriteEnabled());
                      },
              ),
            ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.link, color: conn == null ? _stravaOrange : RwColors.accent),
            title: Text(
              conn == null ? 'Koppel met Strava' : 'Strava',
              style: TextStyle(color: conn == null ? _stravaOrange : null, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(stravaSubtitle,
                style: TextStyle(color: conn?.lastError != null ? RwColors.warning : null)),
            trailing: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            enabled: !_busy,
            onTap: () => _stravaTap(conn),
          ),
        ],
      ),
    );
  }
}

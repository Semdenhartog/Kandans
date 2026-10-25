import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/sync_service.dart';

/// Hier komt de gebruiker terug na het koppelen bij Strava (runwise://app/strava-connected).
class StravaReturnScreen extends ConsumerStatefulWidget {
  const StravaReturnScreen({super.key, required this.status});
  final String status;

  @override
  ConsumerState<StravaReturnScreen> createState() => _StravaReturnScreenState();
}

class _StravaReturnScreenState extends ConsumerState<StravaReturnScreen> {
  String? _message;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _handle();
  }

  Future<void> _handle() async {
    ref.invalidate(stravaConnectionProvider);
    if (widget.status != 'ok') {
      setState(() {
        _done = true;
        _message = switch (widget.status) {
          'denied' => 'Je hebt de koppeling geannuleerd. Je kunt het altijd opnieuw proberen.',
          'scope' => 'Kadans heeft toestemming nodig om je activiteiten te lezen. Probeer het opnieuw en laat dat vinkje aan.',
          'expired' => 'De koppeling duurde te lang. Probeer het opnieuw.',
          _ => 'Koppelen met Strava is niet gelukt. Probeer het later opnieuw.',
        };
      });
      return;
    }
    setState(() => _message = 'Strava is gekoppeld. Je runs worden opgehaald…');
    try {
      final n = await ref.read(syncServiceProvider).syncStrava();
      ref.invalidate(activitiesProvider);
      ref.invalidate(stravaConnectionProvider);
      setState(() => _message = n == 0
          ? 'Strava is gekoppeld. Er waren nog geen runs om op te halen.'
          : 'Strava is gekoppeld en $n run${n == 1 ? '' : 's'} opgehaald, met het weer van dat moment.');
    } catch (e) {
      setState(() => _message = 'Strava is gekoppeld, maar runs ophalen lukte nog niet: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _done = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ok = widget.status == 'ok';
    return Scaffold(
      appBar: AppBar(title: const Text('Strava')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_done)
                const CircularProgressIndicator()
              else
                Icon(ok ? Icons.check_circle_outline : Icons.info_outline,
                    size: 52, color: ok ? RwColors.accent : RwColors.warning),
              const SizedBox(height: 18),
              Text(_message ?? '',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5)),
              const SizedBox(height: 24),
              if (_done)
                FilledButton(
                  onPressed: () => context.go(ok ? '/runs' : '/me'),
                  child: Text(ok ? 'Naar mijn runs' : 'Terug'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

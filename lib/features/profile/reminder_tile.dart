import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/notification_service.dart';
import '../../shared/widgets.dart';
import '../dashboard/dashboard_providers.dart';

/// Instelling in Ik: dagelijkse melding met het beste moment van die dag.
class ReminderTile extends ConsumerStatefulWidget {
  const ReminderTile({super.key});

  @override
  ConsumerState<ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends ConsumerState<ReminderTile> {
  DailyReminderSettings? _s;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await NotificationService.instance.settings();
    if (mounted) setState(() => _s = s);
  }

  /// Nieuwe verwachting ophalen; Vandaag plant de melding dan opnieuw in.
  void _refreshSchedule() => ref.invalidate(forecastProvider);

  Future<void> _toggle(bool on) async {
    final ok = await NotificationService.instance.setEnabled(on);
    if (!mounted) return;
    if (!ok) {
      showMessage(context, 'Geen toestemming voor meldingen. Zet dit aan in de instellingen van je telefoon.', error: true);
    } else if (on) {
      showMessage(context, 'Je krijgt elke dag om ${_s?.timeLabel ?? '07:30'} je beste moment.');
      _refreshSchedule();
    }
    await _load();
  }

  Future<void> _pickTime() async {
    final s = _s;
    if (s == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.hour, minute: s.minute),
      helpText: 'Hoe laat wil je de melding?',
    );
    if (picked == null) return;
    await NotificationService.instance.setTime(picked.hour, picked.minute);
    await _load();
    if (_s?.enabled ?? false) _refreshSchedule();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('Dagelijkse melding'),
          subtitle: Text(s == null
              ? ''
              : s.enabled
                  ? 'Elke dag om ${s.timeLabel}: je beste moment van die dag'
                  : 'Krijg elke ochtend je beste vertrektijd'),
          value: s?.enabled ?? false,
          onChanged: s == null ? null : _toggle,
        ),
        if (s?.enabled ?? false)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Tijdstip melding'),
            trailing: Text(s!.timeLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: _pickTime,
          ),
      ],
    );
  }
}

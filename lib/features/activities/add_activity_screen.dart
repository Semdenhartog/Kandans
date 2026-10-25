import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/location_service.dart';
import '../../data/services/weather_service.dart';
import '../../shared/discard_guard.dart';
import '../../shared/widgets.dart';

/// Handmatig een run toevoegen. Het weer wordt automatisch opgehaald.
class AddActivityScreen extends ConsumerStatefulWidget {
  const AddActivityScreen({super.key});

  @override
  ConsumerState<AddActivityScreen> createState() => _AddActivityScreenState();
}

class _AddActivityScreenState extends ConsumerState<AddActivityScreen> {
  final _form = GlobalKey<FormState>();
  final _distance = TextEditingController();
  final _duration = TextEditingController();
  final _heartRate = TextEditingController();
  DateTime _start = DateTime.now().subtract(const Duration(hours: 1));
  String? _routeId;
  bool _busy = false;

  @override
  void dispose() {
    _distance.dispose();
    _duration.dispose();
    _heartRate.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (time == null || !mounted) return;
    setState(() => _start = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_start.isAfter(DateTime.now())) {
      showMessage(context, 'De starttijd ligt in de toekomst.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final km = Fmt.parseDecimal(_distance.text)!;
      final seconds = Fmt.parseDuration(_duration.text)!;

      // Weer ophalen voor het moment van de run (midden van de run).
      final routes = await ref.read(routesProvider.future).catchError((_) => <RunRoute>[]);
      final route = routes.where((r) => r.id == _routeId).firstOrNull;
      double lat, lon;
      if (route != null) {
        lat = route.startLatitude;
        lon = route.startLongitude;
      } else {
        final loc = await ref.read(weatherLocationProvider.future);
        lat = loc.latitude;
        lon = loc.longitude;
      }
      final mid = _start.add(Duration(seconds: seconds ~/ 2));
      final w = await ref.read(weatherServiceProvider).historical(lat, lon, mid);

      await ref.read(repositoryProvider).addActivity(Activity(
            startedAt: _start,
            distanceMeters: km * 1000,
            movingTimeSeconds: seconds,
            routeId: _routeId,
            averageHeartRate: int.tryParse(_heartRate.text.trim()),
            temperatureCelsius: w?.temperature,
            feelsLikeCelsius: w?.feelsLike,
            windSpeedKmh: w?.windSpeed,
            windDirectionDegrees: w?.windDirection,
            humidityPct: w?.humidity,
          ));
      ref.invalidate(activitiesProvider);
      if (!mounted) return;
      showMessage(
        context,
        w == null ? 'Run opgeslagen (weer kon niet worden opgehaald).' : 'Run opgeslagen met het weer van dat moment.',
      );
      context.go('/runs');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(routesProvider).when(
          data: (r) => r,
          loading: () => const <RunRoute>[],
          error: (_, _) => const <RunRoute>[],
        );
    final km = Fmt.parseDecimal(_distance.text);
    final secs = Fmt.parseDuration(_duration.text);
    final pace = (km != null && km > 0 && secs != null) ? secs / km : null;

    return DiscardGuard(
      dirty: () => !_busy && (_distance.text.isNotEmpty || _duration.text.isNotEmpty || _heartRate.text.isNotEmpty),
      child: Scaffold(
      appBar: AppBar(title: const Text('Run toevoegen')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            InkWell(
              onTap: _pickDateTime,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Gestart op'),
                child: Text('${Fmt.dateLong(_start)} om ${Fmt.time(_start)}'),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _distance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Afstand (km)', hintText: '5,0'),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final d = Fmt.parseDecimal(v ?? '');
                if (d == null || d < 0.1 || d > 300) return 'Vul een afstand in tussen 0,1 en 300 km';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _duration,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Tijd (u:mm:ss of mm:ss)',
                hintText: '28:30',
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final s = Fmt.parseDuration(v ?? '');
                if (s == null || s < 60) return 'Vul je tijd in, bijvoorbeeld 28:30 of 1:05:00';
                return null;
              },
            ),
            if (pace != null && pace > 0) ...[
              const SizedBox(height: 8),
              Text('Gemiddeld tempo: ${Fmt.pace(pace)}', style: TextStyle(color: RwColors.accent)),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _heartRate,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Gemiddelde hartslag (optioneel)'),
              validator: (v) {
                if ((v ?? '').trim().isEmpty) return null;
                final hr = int.tryParse(v!.trim());
                if (hr == null || hr < 30 || hr > 240) return 'Vul een hartslag in tussen 30 en 240';
                return null;
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: _routeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Route (optioneel)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Geen route')),
                for (final r in routes)
                  DropdownMenuItem<String?>(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _routeId = v),
            ),
            const SizedBox(height: 10),
            Text(
              'Het weer tijdens je run (temperatuur, wind, luchtvochtigheid) halen we automatisch op.',
              style: TextStyle(color: RwColors.subtle, fontSize: 13),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: RwColors.accentDark),
                    )
                  : const Text('Opslaan'),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets.dart';

class AddRaceScreen extends ConsumerStatefulWidget {
  const AddRaceScreen({super.key});

  @override
  ConsumerState<AddRaceScreen> createState() => _AddRaceScreenState();
}

class _AddRaceScreenState extends ConsumerState<AddRaceScreen> {
  static const _presets = <String, double>{
    '5 km': 5000,
    '10 km': 10000,
    'Halve marathon': 21097.5,
    'Marathon': 42195,
  };

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _distance = TextEditingController(text: '10');
  final _goal = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 30));
  TimeOfDay? _time;
  String? _routeId;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _distance.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0));
    if (t != null) setState(() => _time = t);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final routes = ref.read(routesProvider).when(
            data: (r) => r,
            loading: () => const <RunRoute>[],
            error: (_, _) => const <RunRoute>[],
          );
      final route = routes.where((r) => r.id == _routeId).firstOrNull;
      await ref.read(repositoryProvider).addRace(RaceEvent(
            name: _name.text.trim(),
            raceDate: _date,
            distanceMeters: Fmt.parseDecimal(_distance.text)! * 1000,
            goalTimeSeconds: Fmt.parseDuration(_goal.text)!,
            startTime: _time == null
                ? null
                : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
            routeId: _routeId,
            startLatitude: route?.startLatitude,
            startLongitude: route?.startLongitude,
          ));
      ref.invalidate(racesProvider);
      if (mounted) context.go('/me/races');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Wedstrijd toevoegen')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Naam', hintText: 'Halve marathon Apeldoorn'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Geef de wedstrijd een naam' : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Datum'),
                      child: Text(Fmt.date(_date)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: _pickTime,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Starttijd'),
                      child: Text(_time == null ? 'Onbekend' : _time!.format(context)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final e in _presets.entries)
                  ActionChip(
                    label: Text(e.key),
                    backgroundColor: RwColors.surfaceHigh,
                    side: const BorderSide(color: RwColors.border),
                    onPressed: () => setState(() =>
                        _distance.text = (e.value / 1000).toString().replaceAll('.', ',')),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _distance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Afstand (km)'),
              validator: (v) {
                final d = Fmt.parseDecimal(v ?? '');
                return d == null || d < 1 || d > 300 ? 'Vul een afstand in tussen 1 en 300 km' : null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _goal,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(labelText: 'Doeltijd (u:mm:ss)', hintText: '1:45:00'),
              validator: (v) {
                final s = Fmt.parseDuration(v ?? '');
                return s == null || s < 300 ? 'Vul een doeltijd in, bijvoorbeeld 1:45:00' : null;
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: _routeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Parcours als route (optioneel)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Geen route')),
                for (final r in routes)
                  DropdownMenuItem<String?>(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _routeId = v),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tip: importeer het parcours als GPX bij Routes. Dan houdt de voorspelling rekening met de wind op het parcours.',
              style: TextStyle(color: RwColors.subtle, fontSize: 13),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Opslaan…' : 'Opslaan'),
            ),
          ],
        ),
      ),
    );
  }
}

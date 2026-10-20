import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/intervals.dart';

/// Kies een gewone run, een standaard intervaltraining of stel er zelf een samen.
/// Geeft null terug als je annuleert; `plan: null` betekent een gewone run.
Future<({IntervalPlan? plan})?> pickIntervalPlan(BuildContext context, {IntervalPlan? current}) {
  return showModalBottomSheet<({IntervalPlan? plan})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PickerSheet(current: current),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({this.current});
  final IntervalPlan? current;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  bool _custom = false;
  int _reps = 6;
  bool _byDistance = true;
  int _workMeters = 400;
  int _workSeconds = 120;
  int _rest = 90;
  int _warmup = 10;
  int _cooldown = 5;

  IntervalPlan get _built => IntervalPlan.build(
        reps: _reps,
        workMeters: _byDistance ? _workMeters : null,
        workSeconds: _byDistance ? null : _workSeconds,
        restSeconds: _rest,
        warmupMin: _warmup,
        cooldownMin: _cooldown,
      );

  String _summary(IntervalPlan p) {
    final total = p.steps.fold<int>(0, (s, x) => s + (x.seconds ?? 0));
    final dist = p.steps.fold<int>(0, (s, x) => s + (x.meters ?? 0));
    final parts = [
      if (total > 0) 'ca. ${(total / 60).round()} min',
      if (dist > 0) '${dist >= 1000 ? (dist / 1000).toStringAsFixed(1).replaceAll('.', ',') : dist} ${dist >= 1000 ? 'km' : 'm'} snel',
    ];
    final rest = p.steps.where((x) => x.kind == StepKind.rest).firstOrNull;
    return [...parts, if (rest != null) '${rest.amount} herstel'].join(' · ');
  }

  Widget _stepper(String label, String value, VoidCallback? minus, VoidCallback? plus) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            IconButton(tooltip: '$label minder', onPressed: minus, icon: const Icon(Icons.remove_circle_outline)),
            SizedBox(
              width: 72,
              child: Text(value, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            IconButton(tooltip: '$label meer', onPressed: plus, icon: const Icon(Icons.add_circle_outline)),
          ],
        ),
      );

  String _t(int s) => s < 60 ? '$s s' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Soort training', style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                'Bij intervallen zegt de stem wanneer je snel moet en wanneer je mag herstellen, ook met je scherm uit.',
                style: TextStyle(color: RwColors.muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              if (!_custom) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.directions_run, color: RwColors.accent),
                    title: const Text('Gewone run'),
                    subtitle: const Text('Zonder intervallen'),
                    trailing: widget.current == null ? const Icon(Icons.check, color: RwColors.accent) : null,
                    onTap: () => Navigator.pop(context, (plan: null)),
                  ),
                ),
                for (final p in IntervalPlan.presets)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.timer_outlined, color: RwColors.accent),
                      title: Text(p.name),
                      subtitle: Text(_summary(p)),
                      trailing: widget.current?.name == p.name ? const Icon(Icons.check, color: RwColors.accent) : null,
                      onTap: () => Navigator.pop(context, (plan: p)),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _custom = true),
                  icon: const Icon(Icons.tune),
                  label: const Text('Zelf samenstellen'),
                ),
              ] else ...[
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Op afstand')),
                    ButtonSegment(value: false, label: Text('Op tijd')),
                  ],
                  selected: {_byDistance},
                  onSelectionChanged: (s) => setState(() => _byDistance = s.first),
                ),
                const SizedBox(height: 8),
                _stepper('Herhalingen', '$_reps×', _reps > 1 ? () => setState(() => _reps--) : null,
                    _reps < 30 ? () => setState(() => _reps++) : null),
                if (_byDistance)
                  _stepper(
                    'Snel stuk',
                    _workMeters >= 1000 ? '${(_workMeters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km' : '$_workMeters m',
                    _workMeters > 100 ? () => setState(() => _workMeters -= _workMeters > 1000 ? 500 : 100) : null,
                    _workMeters < 5000 ? () => setState(() => _workMeters += _workMeters >= 1000 ? 500 : 100) : null,
                  )
                else
                  _stepper('Snel stuk', _t(_workSeconds), _workSeconds > 15 ? () => setState(() => _workSeconds -= _workSeconds > 60 ? 30 : 15) : null,
                      _workSeconds < 1200 ? () => setState(() => _workSeconds += _workSeconds >= 60 ? 30 : 15) : null),
                _stepper('Herstel', _t(_rest), _rest > 0 ? () => setState(() => _rest -= 15) : null,
                    _rest < 600 ? () => setState(() => _rest += 15) : null),
                _stepper('Inlopen', '$_warmup min', _warmup > 0 ? () => setState(() => _warmup--) : null,
                    _warmup < 30 ? () => setState(() => _warmup++) : null),
                _stepper('Uitlopen', '$_cooldown min', _cooldown > 0 ? () => setState(() => _cooldown--) : null,
                    _cooldown < 30 ? () => setState(() => _cooldown++) : null),
                const SizedBox(height: 8),
                Text('${_built.name} · ${_summary(_built)}', style: const TextStyle(color: RwColors.muted)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => setState(() => _custom = false), child: const Text('Terug'))),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, (plan: _built)), child: const Text('Gebruik deze'))),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/strength.dart';
import '../../shared/widgets.dart';

void openStrength(BuildContext context, {String? routineId}) {
  final r = routineId == null ? null : Routine.all.where((x) => x.id == routineId).firstOrNull;
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => r == null ? const StrengthScreen() : RoutinePlayerScreen(routine: r),
  ));
}

IconData _icon(String name) => switch (name) {
      'local_fire_department' => Icons.local_fire_department_outlined,
      'fitness_center' => Icons.fitness_center,
      'self_improvement' => Icons.self_improvement,
      _ => Icons.sports_gymnastics,
    };

/// Kracht en mobiliteit voor lopers: warming-up, kracht en rekken.
class StrengthScreen extends StatelessWidget {
  const StrengthScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Kracht en mobiliteit')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Twee keer per week kracht maakt je sneller en minder blessuregevoelig. Geen materiaal nodig; '
              'de stem telt mee, dus je hoeft niet op je scherm te kijken.',
              style: TextStyle(color: RwColors.muted, height: 1.45),
            ),
            const SizedBox(height: 16),
            for (final (i, r) in Routine.all.indexed)
              StaggerIn(index: i, child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: RwColors.accent.withValues(alpha: 0.15),
                      child: Icon(_icon(r.icon), color: RwColors.accent),
                    ),
                    title: Text(r.title),
                    subtitle: Text('${(r.totalSeconds / 60).round()} min · ${r.exercises.length} oefeningen\n${r.subtitle}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.play_circle_outline, color: RwColors.accent, size: 32),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RoutinePlayerScreen(routine: r))),
                  ),
                ),
              )),
            const SizedBox(height: 8),
            const Text('Pijn bij een oefening? Stop ermee. Twijfel je, vraag een fysiotherapeut.',
                style: TextStyle(color: RwColors.subtle, fontSize: 12)),
          ],
        ),
      );
}

/// Speelt een routine af met een grote klok en de stem.
class RoutinePlayerScreen extends StatefulWidget {
  const RoutinePlayerScreen({super.key, required this.routine});
  final Routine routine;

  @override
  State<RoutinePlayerScreen> createState() => _RoutinePlayerScreenState();
}

class _RoutinePlayerScreenState extends State<RoutinePlayerScreen> {
  late final _p = RoutinePlayer(widget.routine);
  final _tts = FlutterTts();
  Timer? _timer;
  bool _running = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('nl-NL').catchError((_) => null);
    _tts.setSpeechRate(0.5).catchError((_) => null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tts.stop().catchError((_) => null);
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  void _say(String? t) {
    if (t != null) _tts.speak(t).catchError((_) => null);
  }

  void _toggle() {
    if (_p.finished) return;
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    if (!_started) {
      _started = true;
      _say(_p.intro);
      WakelockPlus.enable().catchError((_) {});
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final before = (_p.index, _p.resting);
      final t = _p.tick(1);
      _say(t);
      if ((_p.index, _p.resting) != before) HapticFeedback.mediumImpact();
      if (_p.finished) {
        _timer?.cancel();
        _running = false;
        WakelockPlus.disable().catchError((_) {});
      }
      if (mounted) setState(() {});
    });
    setState(() => _running = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = _p.current;
    final n = _p.next;
    return Scaffold(
      appBar: AppBar(title: Text(widget.routine.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _p.count == 0 ? 0 : _p.index / _p.count,
                  minHeight: 6,
                  color: RwColors.accent,
                  backgroundColor: RwColors.bar,
                ),
              ),
              const SizedBox(height: 6),
              Text(_p.finished ? 'Klaar' : 'Oefening ${_p.index + 1} van ${_p.count}', style: const TextStyle(color: RwColors.subtle)),
              const Spacer(),
              if (c == null) ...[
                const Icon(Icons.check_circle, color: RwColors.good, size: 72),
                const SizedBox(height: 12),
                const Text('Goed gedaan!',
                    textAlign: TextAlign.center, style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 32, fontWeight: FontWeight.w800)),
                Text('${(widget.routine.totalSeconds / 60).round()} minuten ${widget.routine.title.toLowerCase()}.',
                    textAlign: TextAlign.center, style: const TextStyle(color: RwColors.muted)),
              ] else ...[
                Text(_p.resting ? 'PAUZE' : (c.side == null ? 'NU' : 'NU · ${c.side!.toUpperCase()}'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _p.resting ? RwColors.good : RwColors.accent, fontWeight: FontWeight.w800, letterSpacing: 1)),
                const SizedBox(height: 6),
                Text(_p.resting ? 'Hierna: ${n?.name ?? ''}' : c.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 28, fontWeight: FontWeight.w800, height: 1.15)),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(Fmt.duration(_p.remaining.ceil()),
                      style: TextStyle(
                          fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 96, fontWeight: FontWeight.w800, color: _p.resting ? RwColors.good : RwColors.text)),
                ),
                const SizedBox(height: 10),
                Text(_p.resting ? (n?.how ?? '') : c.how,
                    textAlign: TextAlign.center, style: const TextStyle(color: RwColors.muted, height: 1.45, fontSize: 16)),
              ],
              const Spacer(),
              if (!_p.finished) ...[
                if (!_p.resting && n != null)
                  Text('Daarna: ${n.name}${n.side == null ? '' : ' (${n.side})'}',
                      textAlign: TextAlign.center, style: const TextStyle(color: RwColors.subtle)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _toggle,
                      icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                      label: Text(_running ? 'Pauze' : (_started ? 'Verder' : 'Start')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.outlined(
                    tooltip: 'Volgende oefening',
                    onPressed: () => setState(() => _say(_p.skip())),
                    icon: const Icon(Icons.skip_next),
                  ),
                ]),
              ] else
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Sluiten')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Klein blokje "rek even uit" voor na je run.
class CooldownTip extends StatelessWidget {
  const CooldownTip({super.key});

  @override
  Widget build(BuildContext context) => RwCard(
        onTap: () => openStrength(context, routineId: 'cooldown'),
        child: const Row(children: [
          Icon(Icons.self_improvement, color: RwColors.accent, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text('Even rekken? 6 minuten voor kuiten, benen en heupen, met de stem erbij.',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          Icon(Icons.chevron_right, color: RwColors.subtle),
        ]),
      );
}

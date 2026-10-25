import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/sync_service.dart';
import '../../shared/widgets.dart';

const _stravaOrange = Color(0xFFFC5200);

/// Opent "oude runs ophalen uit Strava".
void openStravaHistory(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StravaHistoryScreen()));

enum _State { idle, running, waiting, done, error }

/// Haalt je Strava-runs van vóór het eerste jaar op, in stappen van 200 activiteiten.
/// De voortgang wordt bewaard: stoppen en later verdergaan kan altijd.
class StravaHistoryScreen extends ConsumerStatefulWidget {
  const StravaHistoryScreen({super.key});

  @override
  ConsumerState<StravaHistoryScreen> createState() => _StravaHistoryScreenState();
}

class _StravaHistoryScreenState extends ConsumerState<StravaHistoryScreen> {
  static const _kBefore = 'strava_history_before';
  static const _kTotal = 'strava_history_total';
  static const _kOldest = 'strava_history_oldest';
  static const _kDone = 'strava_history_done';
  static const _waitAfterLimit = Duration(minutes: 15);

  _State _state = _State.idle;
  int? _before;
  int _total = 0;
  DateTime? _oldest;
  String? _error;
  Timer? _resume;
  DateTime? _resumeAt;
  bool _stop = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _stop = true;
    _resume?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _before = p.getInt(_kBefore);
        _total = p.getInt(_kTotal) ?? 0;
        _oldest = DateTime.tryParse(p.getString(_kOldest) ?? '');
        if (p.getBool(_kDone) ?? false) _state = _State.done;
      });
    } catch (_) {}
  }

  Future<void> _save({bool done = false}) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_before != null) await p.setInt(_kBefore, _before!);
      await p.setInt(_kTotal, _total);
      if (_oldest != null) await p.setString(_kOldest, _oldest!.toIso8601String());
      await p.setBool(_kDone, done);
    } catch (_) {}
  }

  Future<void> _start() async {
    HapticFeedback.mediumImpact();
    _resume?.cancel();
    _stop = false;
    setState(() {
      _state = _State.running;
      _error = null;
    });
    final sync = ref.read(syncServiceProvider);
    try {
      while (!_stop && mounted) {
        final page = await sync.stravaHistoryPage(before: _before);
        if (!mounted) return;
        if (page.rateLimited) {
          // Strava staat 100 verzoeken per 15 minuten toe: even wachten en dan vanzelf verder.
          _resumeAt = DateTime.now().add(_waitAfterLimit);
          _resume = Timer(_waitAfterLimit, () {
            if (mounted) _start();
          });
          setState(() => _state = _State.waiting);
          await _save();
          break;
        }
        setState(() {
          _total += page.imported;
          _before = page.nextBefore ?? _before;
          _oldest = page.oldest ?? _oldest;
        });
        await _save(done: page.done);
        if (page.done) {
          HapticFeedback.heavyImpact();
          setState(() => _state = _State.done);
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
      if (_stop && mounted && _state == _State.running) setState(() => _state = _State.idle);
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _State.error;
          _error = friendlyError(e);
        });
      }
    } finally {
      if (mounted) ref.invalidate(activitiesProvider);
    }
  }

  void _pause() {
    _stop = true;
    _resume?.cancel();
    setState(() => _state = _State.idle);
  }

  @override
  Widget build(BuildContext context) {
    final month = _oldest == null ? null : DateFormat('MMMM yyyy', 'nl').format(_oldest!.toLocal());
    final (title, sub) = switch (_state) {
      _State.idle when _total == 0 => ('Al je oude runs', 'Tot nu toe haalde RunWise je laatste jaar uit Strava op. Hier haal je alles op wat daarvoor ligt.'),
      _State.idle => ('Gepauzeerd', 'Tik op Verder om door te gaan waar je was${month == null ? '' : ' ($month)'}.'),
      _State.running => ('Bezig met ophalen…', month == null ? 'Even geduld.' : 'Nu bij $month.'),
      _State.waiting => ('Strava is even druk', 'Strava staat maar een beperkt aantal verzoeken toe. We gaan om ${DateFormat('HH:mm').format(_resumeAt!)} vanzelf verder (laat dit scherm open), of later met de knop.'),
      _State.done => ('Alles binnen', month == null ? 'Er waren geen oudere runs meer.' : 'Je oudste run is van $month.'),
      _State.error => ('Even niet gelukt', _error ?? 'Probeer het later opnieuw.'),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Oude runs uit Strava')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [_stravaOrange.withValues(alpha: 0.28), _stravaOrange.withValues(alpha: 0.02)]),
                border: Border.all(color: _stravaOrange.withValues(alpha: 0.6), width: 2),
              ),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$_total',
                      style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 46, fontWeight: FontWeight.w800, height: 1)),
                  const Text('runs opgehaald', style: TextStyle(color: RwColors.muted, fontSize: 12)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center, style: RwText.title),
          const SizedBox(height: 6),
          Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: RwColors.muted, height: 1.45)),
          const SizedBox(height: 18),
          if (_state == _State.running) const LinearProgressIndicator(minHeight: 4, color: _stravaOrange),
          const SizedBox(height: 22),
          if (_state != _State.done)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _stravaOrange, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52)),
              onPressed: _state == _State.running ? _pause : _start,
              icon: Icon(_state == _State.running ? Icons.pause : Icons.download),
              label: Text(switch (_state) {
                _State.running => 'Pauzeren',
                _State.waiting => 'Nu proberen',
                _ when _total > 0 || _before != null => 'Verder',
                _ => 'Start met ophalen',
              }),
            )
          else
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Naar je runs')),
          const SizedBox(height: 22),
          const _Point(Icons.wb_cloudy_outlined, 'Bij elke run halen we het weer van toen op. Zo leert RunWise beter bij welk weer jij het snelst loopt.'),
          const _Point(Icons.auto_awesome_outlined, 'Runs uit Strava gaan niet naar de AI-coach (voorwaarden van Strava).'),
          const _Point(Icons.save_outlined, 'Je voortgang wordt bewaard. Stoppen en later verdergaan kan altijd.'),
          const SizedBox(height: 10),
          const Text('Gegevens via Strava', textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: RwColors.subtle),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: RwColors.muted, fontSize: 13, height: 1.4))),
        ]),
      );
}

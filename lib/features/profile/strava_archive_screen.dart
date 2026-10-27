import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/sync_service.dart';
import '../../data/services/weather_service.dart';
import '../../domain/best_efforts.dart';
import '../../domain/geo.dart';
import '../../domain/run_file_import.dart';
import '../../domain/run_streams.dart';
import '../../domain/strava_archive.dart';
import '../../domain/zip_reader.dart';
import '../../shared/widgets.dart';

const _stravaOrange = Color(0xFFFC5200);
const _downloadPage = 'https://www.strava.com/athlete/delete_your_account';

/// Opent "Strava-archief importeren".
void openStravaArchive(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StravaArchiveScreen()));

/// Inlezen buiten de hoofdthread, zodat het scherm soepel blijft.
Future<ImportedRun> _parseInBackground(String path, Uint8List bytes, String name) =>
    Isolate.run(() => parseStravaArchiveFile(path, bytes, name: name));

enum _Phase { idle, copying, reading, importing, done, error }

/// Al je runs uit de download van je Strava-account (zip), zonder koppeling met Strava.
class StravaArchiveScreen extends ConsumerStatefulWidget {
  const StravaArchiveScreen({super.key});

  @override
  ConsumerState<StravaArchiveScreen> createState() => _StravaArchiveScreenState();
}

class _StravaArchiveScreenState extends ConsumerState<StravaArchiveScreen> {
  _Phase _phase = _Phase.idle;
  String? _error;
  int _copied = 0;
  int? _size;
  int _total = 0;
  int _done = 0;
  int _added = 0;
  int _skipped = 0;
  int _failed = 0;
  int _otherSports = 0;
  bool _stop = false;
  File? _temp;

  @override
  void dispose() {
    _stop = true;
    WakelockPlus.disable().ignore();
    _cleanup();
    super.dispose();
  }

  void _cleanup() {
    final t = _temp;
    _temp = null;
    if (t != null) t.delete().then((_) {}, onError: (_) {});
  }

  bool get _busy => _phase == _Phase.copying || _phase == _Phase.reading || _phase == _Phase.importing;

  Future<void> _start() async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(type: FileType.any);
    } catch (e) {
      if (mounted) showMessage(context, 'Kiezen is niet gelukt: ${friendlyError(e)}', error: true);
      return;
    }
    if (file == null || !mounted) return;
    if (!file.name.toLowerCase().endsWith('.zip')) {
      showMessage(context, 'Kies het zip-bestand dat je van Strava kreeg (export_….zip).', error: true);
      return;
    }
    setState(() {
      _phase = _Phase.copying;
      _stop = false;
      _error = null;
      _copied = _total = _done = _added = _skipped = _failed = _otherSports = 0;
      _size = null;
    });
    WakelockPlus.enable().ignore();
    ZipReader? zip;
    try {
      // 1. Het archief naar een tijdelijk bestand, zodat we er stukjes uit kunnen lezen.
      _size = await file.length();
      final dir = await getTemporaryDirectory();
      final temp = File('${dir.path}/strava_archief.zip');
      _temp = temp;
      final sink = temp.openWrite();
      var lastTick = DateTime.now();
      await for (final chunk in file.readAsByteStream()) {
        if (_stop) break;
        sink.add(chunk);
        _copied += chunk.length;
        if (DateTime.now().difference(lastTick).inMilliseconds > 200 && mounted) {
          lastTick = DateTime.now();
          setState(() {});
        }
      }
      await sink.close();
      if (_stop) {
        _finish();
        return;
      }

      // 2. De lijst met activiteiten.
      if (mounted) setState(() => _phase = _Phase.reading);
      zip = await ZipReader.open(temp.path);
      final items = await _items(zip);
      if (items.isEmpty) {
        throw RunFileException('Er staan geen hardloopactiviteiten met een bestand in dit archief. '
            'Is dit de zip van Strava (met de map activities)?');
      }

      // 3. Run voor run inlezen en opslaan.
      final existing = await ref.read(activitiesProvider.future).catchError((Object _) => <Activity>[]);
      final starts = [for (final a in existing) a.startedAt];
      final repo = ref.read(repositoryProvider);
      final weather = ref.read(weatherServiceProvider);
      if (mounted) setState(() {
        _phase = _Phase.importing;
        _total = items.length;
      });
      for (final item in items) {
        if (_stop) break;
        try {
          final entry = zip.find(item.file);
          if (entry == null || entry.size > 60 * 1024 * 1024) {
            _failed++;
            continue;
          }
          final bytes = await zip.read(entry);
          final path = item.file, name = item.name;
          final run = await _parseInBackground(path, bytes, name);
          if (starts.any((s) => s.difference(run.start).inMinutes.abs() < 20)) {
            _skipped++;
            continue;
          }
          HourWeather? w;
          final first = run.track.isNotEmpty ? run.track.first : null;
          if (first != null) {
            w = await weather
                .historical(first.lat, first.lon, run.start)
                .timeout(const Duration(seconds: 10))
                .catchError((Object _) => null);
          }
          final streams = RunStreams.fromJson(run.streams);
          final id = await repo.addStravaArchiveRun(
            Activity(
              startedAt: run.start,
              distanceMeters: double.parse(run.distanceMeters.toStringAsFixed(1)),
              movingTimeSeconds: run.movingSeconds,
              source: 'strava',
              averageHeartRate: run.averageHeartRate,
              elevationGainMeters: run.elevationGain == null ? null : double.parse(run.elevationGain!.toStringAsFixed(1)),
              temperatureCelsius: w?.temperature,
              feelsLikeCelsius: w?.feelsLike,
              windSpeedKmh: w?.windSpeed,
              windDirectionDegrees: w?.windDirection,
              humidityPct: w?.humidity,
              trackPolyline: run.track.length >= 2 ? encodePolyline(run.track) : null,
            ),
            item.id,
            streams: run.streams,
            bestEfforts: streams == null ? null : bestEffortsToJson(bestEfforts(streams)),
          );
          if (id == null) {
            _skipped++;
          } else {
            _added++;
            starts.add(run.start);
          }
        } on RunFileException catch (e) {
          if (e.message.startsWith('Dit is geen hardloop')) {
            _otherSports++;
          } else {
            _failed++;
          }
        } catch (_) {
          _failed++;
        } finally {
          _done++;
          if (mounted) setState(() {});
        }
      }
      _finish();
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = e is RunFileException || e is ZipFormatException ? e.toString() : friendlyError(e);
        });
      }
    } finally {
      await zip?.close();
      _cleanup();
      WakelockPlus.disable().ignore();
      if (_added > 0) {
        ref.invalidate(activitiesProvider);
        ref.read(syncServiceProvider).autoLinkRuns().then((_) {}, onError: (_) {});
      }
    }
  }

  void _finish() {
    if (mounted) setState(() => _phase = _Phase.done);
  }

  /// Hardloopactiviteiten met een bestand. Zonder activities.csv: alle bestanden in de map activities.
  Future<List<StravaArchiveItem>> _items(ZipReader zip) async {
    final csv = zip.find('activities.csv');
    if (csv != null) {
      final all = parseStravaActivitiesCsv(utf8.decode(await zip.read(csv), allowMalformed: true));
      _otherSports = all.where((i) => !i.isRun).length;
      return [for (final i in all) if (i.isRun && i.hasFile) i];
    }
    final files = RegExp(r'(^|/)activities/(\d+)\.(gpx|tcx|fit)(\.gz)?$', caseSensitive: false);
    return [
      for (final e in zip.entries)
        if (files.firstMatch(e.name) case final m?) StravaArchiveItem(id: m.group(2)!, name: '', type: '', file: e.name),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final mb = (int b) => (b / (1024 * 1024)).toStringAsFixed(0);
    final (title, sub) = switch (_phase) {
      _Phase.idle => ('Al je runs uit Strava', 'Ook zonder koppeling: vraag bij Strava je archief op en kies hier de zip.'),
      _Phase.copying => ('Archief openen…', _size == null ? '${mb(_copied)} MB' : '${mb(_copied)} van ${mb(_size!)} MB'),
      _Phase.reading => ('Lijst met runs lezen…', 'Even geduld.'),
      _Phase.importing => ('Runs toevoegen…', '$_done van $_total · laat dit scherm open'),
      _Phase.done => (
          _added == 0 ? 'Klaar, niets nieuws' : 'Klaar!',
          [
            '$_added nieuw toegevoegd',
            if (_skipped > 0) '$_skipped stonden er al in',
            if (_otherSports > 0) '$_otherSports andere sporten overgeslagen',
            if (_failed > 0) '$_failed konden niet worden gelezen',
          ].join(' · ')
        ),
      _Phase.error => ('Even niet gelukt', _error ?? 'Probeer het opnieuw.'),
    };
    final progress = switch (_phase) {
      _Phase.copying when (_size ?? 0) > 0 => _copied / _size!,
      _Phase.importing when _total > 0 => _done / _total,
      _Phase.reading || _Phase.copying => null,
      _ => -1.0,
    };

    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _busy) {
          showMessage(context, 'Tik eerst op Stoppen. Wat al is toegevoegd blijft staan.');
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Strava-archief')),
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
                    Text('$_added',
                        style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 46, fontWeight: FontWeight.w800, height: 1, color: RwColors.text)),
                    Text('runs toegevoegd', style: TextStyle(color: RwColors.muted, fontSize: 12)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: RwText.title),
            const SizedBox(height: 6),
            Text(sub, textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted, height: 1.45)),
            const SizedBox(height: 18),
            if (progress == null || progress >= 0)
              LinearProgressIndicator(value: progress, minHeight: 4, color: _stravaOrange),
            const SizedBox(height: 22),
            if (_busy)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => setState(() => _stop = true),
                icon: const Icon(Icons.stop),
                label: Text(_stop ? 'Stoppen…' : 'Stoppen'),
              )
            else if (_phase == _Phase.done && _added > 0)
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.pop(context),
                child: const Text('Naar je runs'),
              )
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: _stravaOrange, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52)),
                onPressed: _start,
                icon: const Icon(Icons.folder_zip_outlined),
                label: Text(_phase == _Phase.idle ? 'Kies het zip-bestand' : 'Opnieuw (andere zip)'),
              ),
            const SizedBox(height: 26),
            Text('Zo vraag je je archief op', style: RwText.title.copyWith(fontSize: 17)),
            const SizedBox(height: 10),
            const _Step(1, 'Log in op strava.com (in je browser, niet in de Strava-app).'),
            const _Step(2, 'Ga naar Instellingen → Mijn account → "Je account downloaden of verwijderen" → Aan de slag.'),
            const _Step(3, 'Kies bij stap 2 "Archief aanvragen". Je account blijft gewoon bestaan.'),
            const _Step(4, 'Je krijgt een e-mail met een link (meestal binnen een paar uur). Download de zip op deze telefoon.'),
            const _Step(5, 'Kies hier dat zip-bestand. Uitpakken hoeft niet.'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(_downloadPage), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open de pagina bij Strava'),
              ),
            ),
            const SizedBox(height: 14),
            const _Point(Icons.directions_run, 'Alleen hardloopactiviteiten (ook trail en loopband). GPX, TCX en FIT van je horloge worden gelezen.'),
            const _Point(Icons.copy_all_outlined, 'Runs die er al in staan (ook via de koppeling of je horloge) worden overgeslagen. Opnieuw proberen kan altijd.'),
            const _Point(Icons.lock_outline, 'Deze runs blijven van jou: ze gaan niet naar de AI-coach en niet naar ranglijsten of Samen.'),
            const _Point(Icons.wifi, 'Het archief kan groot zijn. Gebruik wifi en laat dit scherm open tot het klaar is.'),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.text);
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _stravaOrange.withValues(alpha: 0.15)),
            child: Text('$n', style: const TextStyle(color: _stravaOrange, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: RwColors.muted, fontSize: 13.5, height: 1.4))),
        ]),
      );
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
          Expanded(child: Text(text, style: TextStyle(color: RwColors.muted, fontSize: 13, height: 1.4))),
        ]),
      );
}

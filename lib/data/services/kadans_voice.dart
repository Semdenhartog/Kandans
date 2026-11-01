import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// TESTFASE: de "Kadans-stem" (ElevenLabs, via de edge function `tts`, zodat de sleutel nooit in de app zit).
///
/// Elke zin wordt opgehaald, op de telefoon bewaard (dezelfde zin kost dus maar één keer) en afgespeeld.
/// Lukt dat niet (geen internet, geen sleutel, credits op, te traag), dan valt hij stil terug op de telefoonstem.
/// Zinnen blijven in volgorde en praten nooit door elkaar: de volgende wacht tot de vorige (Kadans- of telefoonstem) klaar is.
class KadansVoice {
  KadansVoice._();
  static final instance = KadansVoice._();

  static const _key = 'kadans_voice_on';
  static const _cacheVersion = 'v1-berend';

  bool? _on;
  DateTime? _pauseUntil;
  AudioPlayer? _player;
  Future<void> _chain = Future<void>.value();

  /// Staat de Kadans-stem aan? Standaard aan tijdens de testfase.
  Future<bool> enabled() async {
    if (_on != null) return _on!;
    try {
      final p = await SharedPreferences.getInstance();
      return _on = p.getBool(_key) ?? true;
    } catch (_) {
      return _on = false;
    }
  }

  Future<void> setEnabled(bool on) async {
    _on = on;
    _pauseUntil = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, on);
    } catch (_) {}
  }

  /// Spreekt [text] uit met de Kadans-stem; lukt dat niet, dan met [fallback] (de telefoonstem).
  void speak(String text, Future<void> Function(String text) fallback) {
    _chain = _chain.then((_) => _speakOne(text, fallback)).catchError((Object _) {});
  }

  Future<void> _speakOne(String text, Future<void> Function(String) fallback) async {
    try {
      final until = _pauseUntil;
      if (!await enabled() || (until != null && DateTime.now().isBefore(until))) {
        await fallback(text);
        return;
      }
      final file = await _cached(text) ?? await _fetch(text);
      if (file == null) {
        await fallback(text);
        return;
      }
      await _play(file);
    } catch (_) {
      // Nooit twee stemmen tegelijk: ook de terugval wacht tot hij klaar is, pas dan de volgende zin.
      await fallback(text).catchError((Object _) {});
    }
  }

  /// Vaste sleutel per zin (FNV-1a, 64 bit), los van de Dart-versie.
  static String _hash(String s) {
    var h = -3750763034362895579; // 0xcbf29ce484222325 als 64-bit int
    for (final c in '$_cacheVersion|$s'.codeUnits) {
      h ^= c;
      h = h * 0x100000001b3; // loopt vanzelf rond binnen 64 bit
    }
    return h.toUnsigned(64).toRadixString(16);
  }

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/kadans_voice');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File?> _cached(String text) async {
    final f = File('${(await _dir()).path}/${_hash(text)}.mp3');
    return await f.exists() && await f.length() > 0 ? f : null;
  }

  Future<File?> _fetch(String text) async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke('tts', body: {'text': text})
          .timeout(const Duration(seconds: 6));
      final data = res.data;
      final bytes = data is Uint8List ? data : (data is List<int> ? Uint8List.fromList(data) : null);
      if (bytes == null || bytes.isEmpty) return null;
      final f = File('${(await _dir()).path}/${_hash(text)}.mp3');
      await f.writeAsBytes(bytes, flush: true);
      return f;
    } on FunctionException catch (e) {
      // Niet ingesteld, credits op of storing: 2 minuten de telefoonstem, daarna opnieuw proberen.
      _pauseUntil = DateTime.now().add(const Duration(minutes: 2));
      return null;
    } catch (_) {
      // Geen internet of te traag: deze zin met de telefoonstem, de volgende probeert het opnieuw.
      return null;
    }
  }

  /// Test de Kadans-stem (zonder cache) en zegt in gewone woorden wat er aan de hand is. Speelt hem af als het werkt.
  Future<String> check() async {
    _pauseUntil = null;
    try {
      final res = await Supabase.instance.client.functions
          .invoke('tts', body: {'text': 'Hoi, dit is de Kadans-stem.'})
          .timeout(const Duration(seconds: 10));
      final data = res.data;
      final bytes = data is Uint8List ? data : (data is List<int> ? Uint8List.fromList(data) : null);
      if (bytes == null || bytes.isEmpty) return 'De Kadans-stem gaf geen geluid terug.';
      final f = File('${(await _dir()).path}/check.mp3');
      await f.writeAsBytes(bytes, flush: true);
      await _play(f);
      return 'De Kadans-stem werkt.';
    } on FunctionException catch (e) {
      final d = e.details;
      final reason = d is Map ? '${d['reason'] ?? ''}' : '';
      if (e.status == 503) return 'Nog niet ingesteld: zet ELEVENLABS_API_KEY in Supabase (Edge Functions → Secrets).';
      if (e.status == 404) return 'De stemfunctie staat nog niet op de server.';
      if (e.status == 401) return 'Log opnieuw in en probeer het nog eens.';
      return switch (reason) {
        'key' => 'De ElevenLabs-sleutel klopt niet. Maak een nieuwe en zet hem opnieuw in Supabase.',
        'permissions' => 'De sleutel mag geen spraak maken: zet "Text to Speech" aan bij de sleutel in ElevenLabs.',
        'quota' => 'Je ElevenLabs-credits zijn op voor deze maand. Je hoort nu de telefoonstem.',
        'voice' => 'Deze stem werkt niet met je ElevenLabs-plan. Kies een andere stem (ELEVENLABS_VOICE_ID).',
        _ => 'ElevenLabs gaf een fout (${d is Map ? d['status'] : e.status}). Je hoort nu de telefoonstem.',
      };
    } catch (_) {
      return 'Geen verbinding met de Kadans-stem. Controleer je internet.';
    }
  }

  Future<void> _play(File f) async {
    final p = _player ??= AudioPlayer()
      ..setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.assistanceNavigationGuidance,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      )).ignore();
    final done = p.onPlayerComplete.first;
    await p.play(DeviceFileSource(f.path));
    await done.timeout(const Duration(seconds: 25), onTimeout: () {});
  }
}

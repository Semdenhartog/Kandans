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
/// Een van de vaste Nederlandse Kadans-stemmen. [key] moet gelijk zijn aan de sleutel in de functie `tts`.
class KadansVoiceOption {
  const KadansVoiceOption(this.key, this.name, this.female, this.style, this.sample);
  final String key;
  final String name;
  final bool female;

  /// Korte omschrijving, bijv. "rustig en warm".
  final String style;

  /// Kort voorbeeld dat de stem voorleest bij "Laat horen".
  final String sample;
}

const kadansVoices = [
  KadansVoiceOption('jamie', 'Jamie', false, 'helder en vriendelijk',
      'Hoi, ik ben Jamie. Kilometer drie. Je tempo is vijf minuut dertig. Lekker bezig!'),
  KadansVoiceOption('marvin', 'Marvin', false, 'energiek en vlot',
      'Hoi, ik ben Marvin. Nog vijfhonderd meter. Hou dit tempo vast, je bent er bijna!'),
  KadansVoiceOption('roos', 'Roos', true, 'fris en vrolijk',
      'Hoi, ik ben Roos. Kilometer drie. Je tempo is vijf minuut dertig. Goed zo!'),
  KadansVoiceOption('sanne', 'Sanne', true, 'kalm en warm',
      'Hoi, ik ben Sanne. Rustig aan bergop. Over tweehonderd meter rechtsaf.'),
];

class KadansVoice {
  KadansVoice._();
  static final instance = KadansVoice._();

  static const _key = 'kadans_voice_on';
  static const _voiceKey = 'kadans_voice_choice';

  bool? _on;
  String? _choice;
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

  /// Gekozen stem (sleutel uit [kadansVoices]); standaard Jamie. Een oude keuze (Berend) wordt Jamie.
  Future<String> choice() async {
    if (_choice != null) return _choice!;
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_voiceKey);
      return _choice = kadansVoices.any((v) => v.key == saved) ? saved! : kadansVoices.first.key;
    } catch (_) {
      return _choice = kadansVoices.first.key;
    }
  }

  Future<void> setChoice(String key) async {
    _choice = key;
    _pauseUntil = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_voiceKey, key);
    } catch (_) {}
  }

  /// Speelt een kort voorbeeld van [option]. Geeft null terug als het lukte, anders een uitleg in gewone woorden.
  Future<String?> preview(KadansVoiceOption option) async {
    await stopPlayback();
    try {
      final file = await _cached(option.sample, option.key) ?? await _fetchOrThrow(option.sample, option.key);
      await _play(file);
      return null;
    } on FunctionException catch (e) {
      return _explain(e);
    } catch (_) {
      return 'Geen verbinding met de Kadans-stem. Controleer je internet.';
    }
  }

  /// Spreekt [text] uit met de Kadans-stem; lukt dat niet, dan met [fallback] (de telefoonstem).
  /// [stopFallback] legt de telefoonstem stil vlak voordat de Kadans-stem begint: nooit twee stemmen tegelijk.
  void speak(String text, Future<void> Function(String text) fallback, {Future<void> Function()? stopFallback}) {
    _chain = _chain.then((_) => _speakOne(text, fallback, stopFallback)).catchError((Object _) {});
  }

  Future<void> _speakOne(String text, Future<void> Function(String) fallback, Future<void> Function()? stopFallback) async {
    var started = false;
    try {
      final until = _pauseUntil;
      if (!await enabled() || (until != null && DateTime.now().isBefore(until))) {
        await fallback(text);
        return;
      }
      final voice = await choice();
      final file = await _cached(text, voice) ?? await _fetch(text, voice);
      if (file == null) {
        await fallback(text);
        return;
      }
      if (stopFallback != null) await stopFallback().catchError((Object _) {});
      started = true;
      await _play(file);
    } catch (_) {
      // Was de Kadans-stem al begonnen, dan niet alsnog de telefoonstem eroverheen.
      if (!started) await fallback(text).catchError((Object _) {});
    }
  }

  /// Zet een lopende Kadans-zin stil (vlak voordat de telefoonstem iets zegt).
  Future<void> stopPlayback() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// Vaste sleutel per zin (FNV-1a, 64 bit), los van de Dart-versie.
  /// De stem zit in de sleutel: wisselen van stem geeft dus nooit een oude opname van een andere stem.
  static String _hash(String s, String voice) {
    var h = -3750763034362895579; // 0xcbf29ce484222325 als 64-bit int
    for (final c in 'v2-$voice|$s'.codeUnits) {
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

  Future<File?> _cached(String text, String voice) async {
    final f = File('${(await _dir()).path}/${_hash(text, voice)}.mp3');
    return await f.exists() && await f.length() > 0 ? f : null;
  }

  /// Haalt de zin op bij de server en bewaart hem. Gooit [FunctionException] bij een serverfout.
  Future<File> _fetchOrThrow(String text, String voice) async {
    final res = await Supabase.instance.client.functions
        .invoke('tts', body: {'text': text, 'voice': voice})
        .timeout(const Duration(seconds: 10));
    final data = res.data;
    final bytes = data is Uint8List ? data : (data is List<int> ? Uint8List.fromList(data) : null);
    if (bytes == null || bytes.isEmpty) throw StateError('leeg');
    final f = File('${(await _dir()).path}/${_hash(text, voice)}.mp3');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<File?> _fetch(String text, String voice) async {
    try {
      return await _fetchOrThrow(text, voice);
    } on FunctionException {
      // Niet ingesteld, credits op of storing: 2 minuten de telefoonstem, daarna opnieuw proberen.
      _pauseUntil = DateTime.now().add(const Duration(minutes: 2));
      return null;
    } catch (_) {
      // Geen internet of te traag: deze zin met de telefoonstem, de volgende probeert het opnieuw.
      return null;
    }
  }

  /// Test de gekozen Kadans-stem (zonder cache) en zegt in gewone woorden wat er aan de hand is. Speelt hem af als het werkt.
  Future<String> check() async {
    _pauseUntil = null;
    try {
      final res = await Supabase.instance.client.functions
          .invoke('tts', body: {'text': 'Hoi, dit is de Kadans-stem.', 'voice': await choice()})
          .timeout(const Duration(seconds: 10));
      final data = res.data;
      final bytes = data is Uint8List ? data : (data is List<int> ? Uint8List.fromList(data) : null);
      if (bytes == null || bytes.isEmpty) return 'De Kadans-stem gaf geen geluid terug.';
      final f = File('${(await _dir()).path}/check.mp3');
      await f.writeAsBytes(bytes, flush: true);
      await _play(f);
      return 'De Kadans-stem werkt.';
    } on FunctionException catch (e) {
      return _explain(e);
    } catch (_) {
      return 'Geen verbinding met de Kadans-stem. Controleer je internet.';
    }
  }

  static String _explain(FunctionException e) {
    final d = e.details;
    final reason = d is Map ? '${d['reason'] ?? ''}' : '';
    if (e.status == 503) return 'Nog niet ingesteld: zet ELEVENLABS_API_KEY in Supabase (Edge Functions → Secrets).';
    if (e.status == 404) return 'De stemfunctie staat nog niet op de server.';
    if (e.status == 401) return 'Log opnieuw in en probeer het nog eens.';
    return switch (reason) {
      'key' => 'De ElevenLabs-sleutel klopt niet. Maak een nieuwe en zet hem opnieuw in Supabase.',
      'permissions' => 'De sleutel mag geen spraak maken: zet "Text to Speech" aan bij de sleutel in ElevenLabs.',
      'quota' => 'Je ElevenLabs-credits zijn op voor deze maand. Je hoort nu de telefoonstem.',
      'voice' => 'Deze stem is nu niet beschikbaar. Kies een andere stem; tot die tijd hoor je de telefoonstem.',
      _ => 'ElevenLabs gaf een fout (${d is Map ? d['status'] : e.status}). Je hoort nu de telefoonstem.',
    };
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';

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
  KadansVoiceOption('daan', 'Daan', false, 'rustig en duidelijk',
      'Hoi, ik ben Daan. Kilometer drie. Je tempo is vijf minuut dertig. Lekker bezig!'),
  KadansVoiceOption('bram', 'Bram', false, 'energiek en vlot',
      'Hoi, ik ben Bram. Nog vijfhonderd meter. Hou dit tempo vast, je bent er bijna!'),
  KadansVoiceOption('emma', 'Emma', true, 'helder en zeker',
      'Hoi, ik ben Emma. Kilometer drie. Je tempo is vijf minuut dertig. Goed zo!'),
  KadansVoiceOption('fleur', 'Fleur', true, 'licht en vrolijk',
      'Hoi, ik ben Fleur. Rustig aan bergop. Over tweehonderd meter rechtsaf.'),
];

class KadansVoice {
  KadansVoice._();
  static final instance = KadansVoice._();

  static const _key = 'kadans_voice_on';
  static const _voiceKey = 'kadans_voice_choice';

  bool? _on;
  String? _choice;
  double? _volume;

  static const _volumeKey = 'kadans_voice_volume';

  /// Zinnen die bijna elke run voorkomen. Worden vóór de start alvast opgehaald, zodat er buiten zonder bereik
  /// geen gat valt (punt 13).
  static const commonPhrases = [
    'Run gestart. Succes!',
    'Gepauzeerd.',
    'We gaan weer.',
    'Automatisch gepauzeerd.',
    'Verder.',
    'Fijn. We gaan verder.',
    'Opdracht overgeslagen.',
    'Gaat het? Tik op je scherm als alles goed is.',
  ];
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

  /// Volume van de Kadans-stem (0,2–1,0), los van het mediavolume (punt 14).
  Future<double> volume() async {
    if (_volume != null) return _volume!;
    try {
      return _volume = (await SharedPreferences.getInstance()).getDouble(_volumeKey) ?? 1.0;
    } catch (_) {
      return _volume = 1.0;
    }
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.2, 1.0);
    try {
      await _player?.setVolume(_volume!);
      await (await SharedPreferences.getInstance()).setDouble(_volumeKey, _volume!);
    } catch (_) {}
  }

  /// Haalt zinnen alvast op (één tegelijk, hooguit 40) zodat ze tijdens de run uit de cache komen.
  /// Stopt bij een serverfout (sleutel, limiet); faalt stil zonder internet.
  Future<void> prefetch(Iterable<String> texts) async {
    if (!await enabled()) return;
    final voice = await choice();
    var n = 0;
    for (final t in texts.toSet()) {
      if (n >= 40) break;
      if (t.trim().isEmpty || t.length > 400) continue;
      if (await _cached(t, voice) != null) continue;
      try {
        await _fetchOrThrow(t, voice);
        n++;
      } catch (_) {
        return;
      }
    }
  }

  /// Gekozen stem (sleutel uit [kadansVoices]); standaard Jamie.
  Future<String> choice() async {
    if (_choice != null) return _choice!;
    try {
      final p = await SharedPreferences.getInstance();
      // Oude keuzes uit eerdere versies (zelfde geslacht).
      final saved = switch (p.getString(_voiceKey)) {
        'berend' || 'jamie' => 'daan',
        'marvin' => 'bram',
        'sanne' || 'anna' => 'emma',
        'roos' => 'fleur',
        final k => k,
      };
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
      return await _playOrExplain(file);
    } on TtsError catch (e) {
      return _explain(e);
    } on TimeoutException {
      return 'De Kadans-stem reageert te traag. Probeer het zo nog eens.';
    } on SocketException {
      return 'Geen verbinding met de Kadans-stem. Controleer je internet.';
    } catch (e) {
      return 'Er ging iets mis met de Kadans-stem ($e).';
    }
  }

  /// Speelt af; lukt het afspelen niet, dan een uitleg (de stem kwam wél binnen).
  Future<String?> _playOrExplain(File f) async {
    try {
      await _play(f);
      return null;
    } catch (e) {
      return 'De stem kwam binnen, maar afspelen lukte niet op deze telefoon ($e).';
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

  /// Vraagt de zin op bij de functie `tts`. Rechtstreeks via http (de bytes komen zo altijd ongeschonden binnen).
  /// Gooit [TtsError] bij een serverfout.
  Future<Uint8List> _request(String text, String voice) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw const TtsError(401, '');
    final res = await http
        .post(
          Uri.parse('${AppConfig.supabaseUrl}/functions/v1/tts'),
          headers: {
            'Authorization': 'Bearer $token',
            'apikey': AppConfig.supabaseAnonKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'text': text, 'voice': voice}),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      var reason = '';
      try {
        final j = jsonDecode(res.body);
        if (j is Map) reason = '${j['reason'] ?? ''}';
      } catch (_) {}
      throw TtsError(res.statusCode, reason);
    }
    if (res.bodyBytes.isEmpty) throw const TtsError(502, 'empty');
    return res.bodyBytes;
  }

  /// Haalt de zin op bij de server en bewaart hem.
  Future<File> _fetchOrThrow(String text, String voice) async {
    final bytes = await _request(text, voice);
    final f = File('${(await _dir()).path}/${_hash(text, voice)}.mp3');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<File?> _fetch(String text, String voice) async {
    try {
      return await _fetchOrThrow(text, voice);
    } on TtsError {
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
      final bytes = await _request('Hoi, dit is de Kadans-stem.', await choice());
      final f = File('${(await _dir()).path}/check.mp3');
      await f.writeAsBytes(bytes, flush: true);
      return await _playOrExplain(f) ?? 'De Kadans-stem werkt.';
    } on TtsError catch (e) {
      return _explain(e);
    } on TimeoutException {
      return 'De Kadans-stem reageert te traag. Probeer het zo nog eens.';
    } on SocketException {
      return 'Geen verbinding met de Kadans-stem. Controleer je internet.';
    } catch (e) {
      return 'Er ging iets mis met de Kadans-stem ($e).';
    }
  }

  static String _explain(TtsError e) {
    final reason = e.reason;
    if (e.status == 503) return 'Nog niet ingesteld: zet GOOGLE_TTS_KEY in Supabase (Edge Functions → Secrets).';
    if (e.status == 404) return 'De stemfunctie staat nog niet op de server.';
    if (e.status == 401) return 'Log opnieuw in en probeer het nog eens.';
    return switch (reason) {
      'key_restricted' => 'De Google-sleutel mag Text-to-Speech niet gebruiken. Zet bij de sleutel "Cloud Text-to-Speech API" aan.',
      'key' => 'De stemsleutel klopt niet. Maak een nieuwe en zet hem opnieuw in Supabase (GOOGLE_TTS_KEY).',
      'api_off' => 'Zet in Google Cloud de "Cloud Text-to-Speech API" aan. Tot die tijd hoor je de telefoonstem.',
      'billing' => 'Zet in Google Cloud betalen aan voor dit project (het gratis deel blijft gratis).',
      'permissions' => 'De sleutel mag geen spraak maken. Controleer de rechten van de sleutel.',
      'plan' => 'Deze stem werkt pas met een betaald ElevenLabs-plan. Je hoort nu de telefoonstem.',
      'quota' => 'Het gratis aantal stemzinnen is op voor deze maand. Je hoort nu de telefoonstem.',
      'voice' => 'Deze stem is nu niet beschikbaar. Kies een andere stem; tot die tijd hoor je de telefoonstem.',
      _ => 'De stemdienst gaf een fout (${e.status}). Je hoort nu de telefoonstem.',
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
    await p.setVolume(await volume());
    final done = p.onPlayerComplete.first;
    await p.play(DeviceFileSource(f.path));
    await done.timeout(const Duration(seconds: 25), onTimeout: () {});
  }
}

/// Fout van de functie `tts` (HTTP-status + reden uit het antwoord).
class TtsError implements Exception {
  const TtsError(this.status, this.reason);
  final int status;
  final String reason;

  @override
  String toString() => 'TtsError($status, $reason)';
}

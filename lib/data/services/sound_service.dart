import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eigen Kadans-geluidjes (zelf gemaakt, in assets/sounds): start, elke km, intervalwissel, record en finish.
/// Muziek wordt even zachter gezet in plaats van gestopt.
enum RwSound { start, km, interval, record, finish }

class SoundService {
  SoundService._();
  static final instance = SoundService._();

  static const _key = 'sounds_on';
  AudioPlayer? _player;
  bool? _on;

  Future<bool> enabled() async {
    if (_on != null) return _on!;
    try {
      final p = await SharedPreferences.getInstance();
      _on = p.getBool(_key) ?? true;
    } catch (_) {
      _on = true;
    }
    return _on!;
  }

  Future<void> setEnabled(bool on) async {
    _on = on;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, on);
    } catch (_) {}
  }

  Future<void> play(RwSound s) async {
    try {
      if (!await enabled()) return;
      final player = _player ??= AudioPlayer()
        ..setAudioContext(AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        )).ignore();
      await player.stop();
      await player.play(AssetSource('sounds/${s.name}.wav'), volume: 0.8);
    } catch (_) {
      // Geluid is een extraatje.
    }
  }

  /// Piepje voor het aftellen 3-2-1 (punt 53): kort en midden voor 3, 2, 1; hoger en langer bij start.
  Future<void> beep({bool go = false}) async {
    try {
      if (!await enabled()) return;
      final player = _beeper ??= AudioPlayer()
        ..setAudioContext(AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        )).ignore();
      await player.stop();
      await player.play(BytesSource(go ? (_goWav ??= toneWav(1320, 0.45)) : (_tickWav ??= toneWav(880, 0.16)), mimeType: 'audio/wav'),
          volume: 0.9);
    } catch (_) {}
  }

  AudioPlayer? _beeper;
  Uint8List? _tickWav, _goWav;
}

/// Eenvoudige sinustoon als WAV (mono, 16 bit), met zachte in- en uitloop zodat hij niet klikt.
Uint8List toneWav(double freq, double seconds, {int sampleRate = 22050}) {
  final n = (sampleRate * seconds).round();
  final pcm = Int16List(n);
  final fade = (sampleRate * 0.01).round();
  for (var i = 0; i < n; i++) {
    final env = i < fade ? i / fade : (i > n - fade ? (n - i) / fade : 1.0);
    pcm[i] = (math.sin(2 * math.pi * freq * i / sampleRate) * env * 0.6 * 32767).round();
  }
  final data = pcm.buffer.asUint8List();
  final h = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + data.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, 1, Endian.little);
  h.setUint32(24, sampleRate, Endian.little);
  h.setUint32(28, sampleRate * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, data.length, Endian.little);
  return Uint8List.fromList([...h.buffer.asUint8List(), ...data]);
}

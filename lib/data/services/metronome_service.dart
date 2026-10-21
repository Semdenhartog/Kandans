import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// Maakt een WAV-bestand met [beats] tikken op [spm] stappen per minuut (zachte houtblok-tik).
/// Elke tik is kort en zacht, zodat hij boven muziek uit hoorbaar is zonder te storen.
Uint8List metronomeWav(int spm, {int beats = 8, int sampleRate = 22050}) {
  final beatSamples = (sampleRate * 60 / spm).round();
  final total = beatSamples * beats;
  final pcm = Int16List(total);
  final click = (sampleRate * 0.03).round();
  for (var b = 0; b < beats; b++) {
    final accent = b % 2 == 0; // Linker- en rechtervoet iets verschillend.
    final freq = accent ? 1800.0 : 1500.0;
    for (var i = 0; i < click; i++) {
      final t = i / sampleRate;
      final env = math.exp(-t * 140);
      pcm[b * beatSamples + i] = (math.sin(2 * math.pi * freq * t) * env * 0.5 * 32767).round();
    }
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
  h.setUint16(20, 1, Endian.little); // PCM
  h.setUint16(22, 1, Endian.little); // mono
  h.setUint32(24, sampleRate, Endian.little);
  h.setUint32(28, sampleRate * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, data.length, Endian.little);
  return Uint8List.fromList([...h.buffer.asUint8List(), ...data]);
}

/// Cadans-tik tijdens het lopen: helpt je om kortere, snellere passen te maken.
class MetronomeService {
  MetronomeService._();
  static final instance = MetronomeService._();

  AudioPlayer? _player;
  int? _spm;

  bool get running => _spm != null;

  Future<void> start(int spm) async {
    if (_spm == spm) return;
    await stop();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/runwise_tik_$spm.wav');
      if (!file.existsSync()) await file.writeAsBytes(metronomeWav(spm));
      final player = _player ??= AudioPlayer();
      // Geen audiofocus vragen: muziek mag gewoon doorspelen.
      await player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
      ));
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(DeviceFileSource(file.path), volume: 0.6);
      _spm = spm;
    } catch (_) {
      _spm = null;
    }
  }

  Future<void> pause() async {
    try {
      await _player?.pause();
    } catch (_) {}
  }

  Future<void> resume() async {
    if (_spm == null) return;
    try {
      await _player?.resume();
    } catch (_) {}
  }

  Future<void> stop() async {
    _spm = null;
    try {
      await _player?.stop();
    } catch (_) {}
  }
}

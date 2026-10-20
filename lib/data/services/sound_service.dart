import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eigen RunWise-geluidjes (zelf gemaakt, in assets/sounds): start, elke km, intervalwissel, record en finish.
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
}

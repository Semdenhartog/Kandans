import 'heart_rate.dart';

/// Hartslagalarm tijdens een run: meldt als je hartslag te lang boven een zone zit.
///
/// [limitZone] 0 = uit; 2 betekent "alarm zodra je boven zone 2 zit" (zone 3 of hoger).
/// Het alarm wacht [holdSeconds] seconden (een piekje telt niet) en herhaalt pas na [cooldownSeconds].
class HrAlarm {
  HrAlarm({this.limitZone = 0, this.holdSeconds = 15, this.cooldownSeconds = 90});

  final int limitZone;
  final int holdSeconds;
  final int cooldownSeconds;

  int _over = 0;
  int _cool = 0;

  bool get enabled => limitZone >= 1 && limitZone <= 4;

  /// Roep elke seconde aan. Geeft true als er nu een melding moet komen.
  bool tick(int? bpm, int maxHr) {
    if (!enabled) return false;
    if (_cool > 0) _cool--;
    if (bpm == null || bpm <= 0 || heartRateZone(bpm, maxHr) <= limitZone) {
      _over = 0;
      return false;
    }
    _over++;
    if (_over >= holdSeconds && _cool == 0) {
      _cool = cooldownSeconds;
      _over = 0;
      return true;
    }
    return false;
  }
}

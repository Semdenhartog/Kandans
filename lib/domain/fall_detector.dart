import 'dart:math' as math;

/// Valdetectie tijdens een run, op de versnellingsmeter van de telefoon (m/s², inclusief zwaartekracht).
///
/// 1. Een harde klap (veel harder dan een gewone pas).
/// 2. Daarna een paar seconden om bij te komen.
/// 3. Dan [stillSeconds] seconden bijna geen beweging, met de telefoon niet rechtop
///    (in je zak of armband staat hij rechtop zolang je staat of loopt).
///
/// Lopen geeft ook klappen, maar daarna beweeg je meteen weer: dan wordt het afgeblazen.
class FallDetector {
  FallDetector({this.impact = 30, this.settle = 3, this.stillSeconds = 12, this.moveLimit = 2.2});

  /// Klap in m/s² (± 3 g).
  final double impact;

  /// Seconden na de klap die niet meetellen (vallen, rollen, stilvallen).
  final double settle;
  final double stillSeconds;

  /// Hoeveel |a| van 9,81 mag afwijken om nog als "stil" te tellen.
  final double moveLimit;

  double? _impactAt;
  double _uprightSum = 0;
  int _samples = 0;
  bool _fired = false;

  bool get watching => _impactAt != null;

  /// Geeft één keer true als een val vermoed wordt.
  bool add(double t, double x, double y, double z) {
    final mag = math.sqrt(x * x + y * y + z * z);
    final start = _impactAt;
    if (start == null) {
      if (mag >= impact) {
        _impactAt = t;
        _uprightSum = 0;
        _samples = 0;
        _fired = false;
      }
      return false;
    }
    final since = t - start;
    if (since < settle) return false;
    if ((mag - 9.81).abs() > moveLimit) {
      // Weer in beweging: geen val (of je bent al opgestaan).
      reset();
      return false;
    }
    _samples++;
    _uprightSum += (y.abs() / math.max(mag, 0.1));
    if (since >= settle + stillSeconds && !_fired) {
      final upright = _uprightSum / math.max(_samples, 1);
      _fired = true;
      _impactAt = null;
      // Rechtop (staan, wachten bij een stoplicht): geen val.
      return upright < 0.75;
    }
    return false;
  }

  void reset() {
    _impactAt = null;
    _uprightSum = 0;
    _samples = 0;
  }
}

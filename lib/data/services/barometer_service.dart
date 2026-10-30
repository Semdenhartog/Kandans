import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../domain/barometer.dart';

/// Luchtdrukmeter van de telefoon voor nauwkeurige hoogtemeters tijdens het lopen.
/// Heeft je telefoon er geen (veel goedkopere toestellen), dan gebeurt er niets en
/// gebruikt Kadans de GPS-hoogte en de hoogtekaart, zoals altijd.
class BarometerService {
  BarometerService._();
  static final instance = BarometerService._();

  final _altimeter = BarometricAltimeter();
  StreamSubscription<BarometerEvent>? _sub;

  /// Null = nog onbekend, false = deze telefoon heeft geen barometer.
  bool? available;

  /// Gladgestreken barometerhoogte (m), of null.
  double? get altitude => _altimeter.altitude;

  void start() {
    if (_sub != null || available == false) return;
    _altimeter.reset();
    try {
      _sub = barometerEventStream(samplingPeriod: SensorInterval.normalInterval).listen(
        (e) {
          available = true;
          _altimeter.add(e.pressure);
        },
        onError: (Object e) {
          // NO_SENSOR: geen barometer in dit toestel.
          debugPrint('Barometer: $e');
          available = false;
          stop();
        },
        cancelOnError: true,
      );
    } catch (_) {
      available = false;
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}

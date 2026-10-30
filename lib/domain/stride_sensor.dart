// Loopsensor via Bluetooth: de standaard "Running Speed and Cadence"-dienst (0x1814, meting 0x2A53).
// Werkt met voetsensoren (Stryd, Polar Stride, Garmin, Wahoo) en sommige borstbanden (Wahoo Tickr X, Garmin HRM-Pro).
// Gebaseerd op OpenTracks (Apache License 2.0, BluetoothHandlerRunningSpeedAndCadence), met twee verbeteringen:
// het loop/wandel-bit is bit 2 (daar stond 0x03), en de cadans wordt altijd in stappen per minuut gegeven.

/// Eén meting van een loopsensor.
class StrideData {
  const StrideData({this.speed, this.cadence, this.strideLength, this.totalDistance, this.running});

  /// Snelheid in m/s.
  final double? speed;

  /// Stappen per minuut (beide voeten samen).
  final int? cadence;

  /// Paslengte in meters.
  final double? strideLength;

  /// Totale afstand volgens de sensor (m), sinds hij aan staat.
  final double? totalDistance;

  /// Rennen (true) of wandelen (false), als de sensor dat meldt.
  final bool? running;
}

int _u16(List<int> d, int i) => d[i] | (d[i + 1] << 8);
int _u32(List<int> d, int i) => d[i] | (d[i + 1] << 8) | (d[i + 2] << 16) | (d[i + 3] << 24);

/// Leest een RSC-meting (0x2A53). Null bij een te kort pakket.
StrideData? parseRunningSpeedCadence(List<int> d) {
  if (d.length < 4) return null;
  final flags = d[0];
  final hasStride = flags & 0x01 != 0;
  final hasTotal = flags & 0x02 != 0;
  final running = flags & 0x04 != 0;
  final speed = _u16(d, 1) / 256.0;
  final rawCadence = d[3];
  var i = 4;
  double? stride;
  if (hasStride && d.length >= i + 2) {
    stride = _u16(d, i) / 100.0;
    i += 2;
  }
  double? total;
  if (hasTotal && d.length >= i + 4) {
    total = _u32(d, i) / 10.0;
  }
  return StrideData(
    speed: speed,
    cadence: normalizeCadence(rawCadence, speed: speed),
    strideLength: stride,
    totalDistance: total,
    running: running,
  );
}

/// Sensoren geven de cadans in stappen per minuut (±170 bij hardlopen) of in "omwentelingen"
/// van één been (±85). Onder de 110 bij looptempo verdubbelen we naar stappen per minuut.
int? normalizeCadence(int raw, {double? speed}) {
  if (raw <= 0) return null;
  final runningSpeed = speed == null || speed > 1.6;
  final spm = raw < 110 && runningSpeed ? raw * 2 : raw;
  return spm > 260 ? null : spm;
}

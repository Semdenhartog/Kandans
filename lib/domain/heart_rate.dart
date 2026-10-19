/// Leest een meting van de standaard hartslag-dienst (Bluetooth 0x2A37).
/// Byte 0 = vlaggen; bit 0 zegt of de hartslag 8 of 16 bits is.
int? parseHeartRateMeasurement(List<int> data) {
  if (data.length < 2) return null;
  final flags = data[0];
  final sixteen = (flags & 0x01) == 1;
  if (sixteen) {
    if (data.length < 3) return null;
    return data[1] | (data[2] << 8);
  }
  return data[1];
}

/// Hartslagzone 1 t/m 5 op basis van je maximale hartslag (50-60-70-80-90%).
int heartRateZone(int bpm, int maxHr) {
  if (maxHr <= 0) return 0;
  final f = bpm / maxHr;
  if (f < 0.6) return 1;
  if (f < 0.7) return 2;
  if (f < 0.8) return 3;
  if (f < 0.9) return 4;
  return 5;
}

const heartRateZoneNames = {
  1: 'Herstel',
  2: 'Rustig',
  3: 'Tempo',
  4: 'Drempel',
  5: 'Maximaal',
};

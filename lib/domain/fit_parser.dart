import 'dart:typed_data';

/// Eén meetpunt uit een FIT-bestand (Garmin en andere horloges).
class FitPoint {
  FitPoint(this.time, {this.lat, this.lon, this.altitude, this.heartRate, this.distance});
  final DateTime time;
  final double? lat;
  final double? lon;
  final double? altitude;
  final int? heartRate;
  final double? distance;
}

class FitData {
  FitData(this.points, {this.sport});
  final List<FitPoint> points;

  /// FIT-sportnummer: 1 = hardlopen, 2 = fietsen, 11 = wandelen, enz. Null als het er niet in staat.
  final int? sport;
  bool get isRunning => sport == null || sport == 1;
}

class FitFormatException implements Exception {
  FitFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _FieldDef {
  _FieldDef(this.num, this.size, this.baseType);
  final int num;
  final int size;
  final int baseType;
}

class _MsgDef {
  _MsgDef(this.global, this.bigEndian, this.fields, this.devSize);
  final int global;
  final bool bigEndian;
  final List<_FieldDef> fields;
  final int devSize;
}

/// FIT-tijd telt vanaf 31 dec 1989 (UTC).
const _fitEpoch = 631065600;
const _semicircle = 180 / 2147483648;

/// Leest de meetpunten (berichtsoort "record") en de sport uit een FIT-bestand.
/// Alleen wat een run nodig heeft: tijd, positie, hoogte, hartslag en afstand.
FitData parseFit(Uint8List bytes) {
  if (bytes.length < 14) throw FitFormatException('Dit FIT-bestand is te kort.');
  final data = ByteData.sublistView(bytes);
  final headerSize = bytes[0];
  if (headerSize < 12 || bytes.length < headerSize) throw FitFormatException('Geen geldig FIT-bestand.');
  if (String.fromCharCodes(bytes.sublist(8, 12)) != '.FIT') throw FitFormatException('Geen geldig FIT-bestand.');
  final dataSize = data.getUint32(4, Endian.little);
  final end = (headerSize + dataSize).clamp(headerSize, bytes.length);

  final defs = <int, _MsgDef>{};
  final points = <FitPoint>[];
  int? sport;
  int? lastTimestamp;
  var pos = headerSize;

  int readUint(int at, int size, bool big) {
    final e = big ? Endian.big : Endian.little;
    switch (size) {
      case 1:
        return data.getUint8(at);
      case 2:
        return data.getUint16(at, e);
      case 4:
        return data.getUint32(at, e);
      default:
        return -1;
    }
  }

  while (pos < end) {
    final header = bytes[pos++];
    int local;
    int? compressedOffset;
    if (header & 0x80 != 0) {
      // Compacte kop met tijdsverschil.
      local = (header >> 5) & 0x03;
      compressedOffset = header & 0x1F;
    } else {
      local = header & 0x0F;
      if (header & 0x40 != 0) {
        // Definitie van een berichtsoort.
        if (pos + 5 > end) break;
        final big = bytes[pos + 1] == 1;
        final global = readUint(pos + 2, 2, big);
        final n = bytes[pos + 4];
        pos += 5;
        if (pos + n * 3 > end) break;
        final fields = <_FieldDef>[
          for (var i = 0; i < n; i++) _FieldDef(bytes[pos + i * 3], bytes[pos + i * 3 + 1], bytes[pos + i * 3 + 2]),
        ];
        pos += n * 3;
        var devSize = 0;
        if (header & 0x20 != 0) {
          if (pos >= end) break;
          final nd = bytes[pos++];
          if (pos + nd * 3 > end) break;
          for (var i = 0; i < nd; i++) {
            devSize += bytes[pos + i * 3 + 1];
          }
          pos += nd * 3;
        }
        defs[local] = _MsgDef(global, big, fields, devSize);
        continue;
      }
    }

    final def = defs[local];
    if (def == null) throw FitFormatException('Dit FIT-bestand is beschadigd.');
    final size = def.fields.fold<int>(0, (s, f) => s + f.size) + def.devSize;
    if (pos + size > end) break;

    int? timestamp;
    int? lat, lon, alt, enhAlt, hr, dist, sportField;
    var at = pos;
    for (final f in def.fields) {
      final v = readUint(at, f.size, def.bigEndian);
      at += f.size;
      if (v < 0) continue;
      final invalid = switch (f.size) { 1 => v == 0xFF, 2 => v == 0xFFFF, _ => v == 0xFFFFFFFF };
      final signedInvalid = f.size == 4 && v == 0x7FFFFFFF;
      if (invalid || signedInvalid) continue;
      if (f.num == 253) {
        timestamp = v;
        continue;
      }
      switch (def.global) {
        case 20: // record
          switch (f.num) {
            case 0:
              lat = v.toSigned(32);
            case 1:
              lon = v.toSigned(32);
            case 2:
              alt = v;
            case 78:
              enhAlt = v;
            case 3:
              hr = v;
            case 5:
              dist = v;
          }
        case 18: // session
          if (f.num == 5) sportField = v;
        case 12: // sport
          if (f.num == 0) sportField = v;
      }
    }
    pos += size;

    if (compressedOffset != null && lastTimestamp != null) {
      var t = (lastTimestamp & ~0x1F) | compressedOffset;
      if (compressedOffset < (lastTimestamp & 0x1F)) t += 0x20;
      timestamp = t;
    }
    if (timestamp != null) lastTimestamp = timestamp;

    if (sportField != null && (def.global == 18 || sport == null)) sport = sportField;
    if (def.global != 20 || timestamp == null) continue;
    final altitude = enhAlt ?? alt;
    points.add(FitPoint(
      DateTime.fromMillisecondsSinceEpoch((timestamp + _fitEpoch) * 1000, isUtc: true),
      lat: lat == null || lon == null ? null : lat * _semicircle,
      lon: lat == null || lon == null ? null : lon * _semicircle,
      altitude: altitude == null ? null : altitude / 5 - 500,
      heartRate: hr,
      distance: dist == null ? null : dist / 100,
    ));
  }
  return FitData(points, sport: sport);
}

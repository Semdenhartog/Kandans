import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'geo.dart';
import 'route_geometry.dart';
import 'route_turns.dart';

/// Maakt een FIT-koersbestand (.fit), het eigen formaat van Garmin (ook gelezen door
/// Coros, Wahoo en Hammerhead). Anders dan een GPX-bestand zitten hier afslagpunten in:
/// het horloge trilt dan vóór elke afslag en toont "Linksaf" of "Rechtsaf".
///
/// Opbouw volgens de FIT-specificatie: file_id, course, lap, event (start), records
/// (de lijn), course_points (de afslagen) en event (stop).
Uint8List buildFitCourse(
  String name,
  List<LatLng> points, {
  List<RouteTurn>? turns,
  List<ElevationSample> profile = const [],
  double paceSecondsPerKm = 360,
  DateTime? start,
}) {
  final track = RouteTrack(points);
  if (!track.isValid) throw ArgumentError('Route heeft te weinig punten');
  final t0 = _fitTime(start ?? DateTime.now());
  final speed = 1000 / paceSecondsPerKm; // m/s, voor de virtuele partner.
  int timeAt(double meters) => t0 + (meters / speed).round();
  final allTurns = turns ?? detectTurns(track);
  final scale = profile.isEmpty ? 0.0 : profile.last.meters / track.length;

  final w = _FitWriter();

  // file_id: type = course (6), fabrikant = development (255).
  w.define(0, 0, [
    (0, 1, _enum),
    (1, 2, _uint16),
    (2, 2, _uint16),
    (3, 4, _uint32z),
    (4, 4, _uint32),
  ]);
  w.data(0, (b) {
    b.u8(6);
    b.u16(255);
    b.u16(1);
    b.u32(0x52570001);
    b.u32(t0);
  });

  // course: naam en sport = hardlopen (1).
  w.define(1, 31, [(4, 1, _enum), (5, 16, _string)]);
  w.data(1, (b) {
    b.u8(1);
    b.str(name, 16);
  });

  // lap: start, eind, tijd en afstand van de hele koers.
  final first = points.first, last = points.last;
  final totalMs = ((timeAt(track.length) - t0) * 1000);
  w.define(2, 19, [
    (253, 4, _uint32),
    (2, 4, _uint32),
    (3, 4, _sint32),
    (4, 4, _sint32),
    (5, 4, _sint32),
    (6, 4, _sint32),
    (7, 4, _uint32),
    (8, 4, _uint32),
    (9, 4, _uint32),
  ]);
  w.data(2, (b) {
    b.u32(t0);
    b.u32(t0);
    b.s32(_semi(first.lat));
    b.s32(_semi(first.lon));
    b.s32(_semi(last.lat));
    b.s32(_semi(last.lon));
    b.u32(totalMs);
    b.u32(totalMs);
    b.u32((track.length * 100).round());
  });

  // event: timer start (event 0, type 0) en aan het eind stop_disable_all (type 9).
  w.define(3, 21, [(253, 4, _uint32), (0, 1, _enum), (1, 1, _enum), (4, 1, _uint8)]);
  w.data(3, (b) {
    b.u32(t0);
    b.u8(0);
    b.u8(0);
    b.u8(0);
  });

  // record: de lijn van de route (hoogte met schaal 5 en offset 500).
  w.define(4, 20, [(253, 4, _uint32), (0, 4, _sint32), (1, 4, _sint32), (5, 4, _uint32), (2, 2, _uint16)]);
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final m = track.cumulative[i];
    final ele = p.ele ?? (profile.isEmpty ? null : elevationAt(profile, m * scale));
    w.data(4, (b) {
      b.u32(timeAt(m));
      b.s32(_semi(p.lat));
      b.s32(_semi(p.lon));
      b.u32((m * 100).round());
      b.u16(ele == null ? 0xFFFF : ((ele + 500) * 5).round().clamp(0, 0xFFFE).toInt());
    });
  }

  // course_point: de afslagen.
  w.define(5, 32, [
    (254, 2, _uint16),
    (1, 4, _uint32),
    (2, 4, _sint32),
    (3, 4, _sint32),
    (4, 4, _uint32),
    (5, 1, _enum),
    (6, 16, _string),
  ]);
  for (var i = 0; i < allTurns.length; i++) {
    final t = allTurns[i];
    w.data(5, (b) {
      b.u16(i);
      b.u32(timeAt(t.meters));
      b.s32(_semi(t.point.lat));
      b.s32(_semi(t.point.lon));
      b.u32((t.meters * 100).round());
      b.u8(fitCoursePointType(t.kind));
      b.str(t.kind.label, 16);
    });
  }

  w.data(3, (b) {
    b.u32(timeAt(track.length));
    b.u8(0);
    b.u8(9);
    b.u8(0);
  });

  return w.finish();
}

/// FIT course_point-type voor een afslag (uit het FIT-profiel).
int fitCoursePointType(TurnKind k) => switch (k) {
      TurnKind.left => 6,
      TurnKind.right => 7,
      TurnKind.slightLeft => 19,
      TurnKind.sharpLeft => 20,
      TurnKind.slightRight => 21,
      TurnKind.sharpRight => 22,
      TurnKind.uTurn => 23,
    };

// FIT-basistypen.
const _enum = 0x00;
const _uint8 = 0x02;
const _uint16 = 0x84;
const _sint32 = 0x85;
const _uint32 = 0x86;
const _string = 0x07;
const _uint32z = 0x8C;

/// FIT telt seconden vanaf 31 december 1989 (UTC).
int _fitTime(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 - 631065600;

/// Graden naar "semicircles" (2^31 / 180).
int _semi(double deg) => (deg * (math.pow(2, 31) / 180)).round().clamp(-0x7FFFFFFF, 0x7FFFFFFF).toInt();

class _Bytes {
  final _b = BytesBuilder();
  void u8(int v) => _b.addByte(v & 0xFF);
  void u16(int v) {
    u8(v);
    u8(v >> 8);
  }

  void u32(int v) {
    u16(v);
    u16(v >> 16);
  }

  void s32(int v) => u32(v & 0xFFFFFFFF);

  /// Tekst met vaste lengte, altijd afgesloten met een 0-byte.
  void str(String s, int size) {
    var bytes = utf8.encode(s);
    // Niet midden in een teken afkappen.
    while (bytes.length > size - 1) {
      s = s.substring(0, s.length - 1);
      bytes = utf8.encode(s);
    }
    _b.add(bytes);
    for (var i = bytes.length; i < size; i++) {
      u8(0);
    }
  }

  int get length => _b.length;
  Uint8List take() => _b.takeBytes();
}

class _FitWriter {
  final _data = _Bytes();
  final _sizes = <int, int>{};

  /// Definitiebericht: lokaal nummer [local] staat voor globaal bericht [global] met deze velden (nummer, grootte, type).
  void define(int local, int global, List<(int, int, int)> fields) {
    _data
      ..u8(0x40 | local)
      ..u8(0)
      ..u8(0) // little endian
      ..u16(global)
      ..u8(fields.length);
    for (final f in fields) {
      _data
        ..u8(f.$1)
        ..u8(f.$2)
        ..u8(f.$3);
    }
    _sizes[local] = fields.fold(0, (s, f) => s + f.$2);
  }

  void data(int local, void Function(_Bytes b) write) {
    final before = _data.length;
    _data.u8(local);
    write(_data);
    final written = _data.length - before - 1;
    assert(written == _sizes[local], 'FIT-bericht $local: $written bytes, verwacht ${_sizes[local]}');
  }

  Uint8List finish() {
    final body = _data.take();
    final header = _Bytes()
      ..u8(14)
      ..u8(0x20) // protocol 2.0
      ..u16(2132) // profielversie 21.32
      ..u32(body.length);
    final h = header.take();
    final head = BytesBuilder()
      ..add(h)
      ..add(ascii.encode('.FIT'));
    final head12 = head.takeBytes();
    final headerCrc = fitCrc(head12);
    final out = BytesBuilder()
      ..add(head12)
      ..addByte(headerCrc & 0xFF)
      ..addByte(headerCrc >> 8)
      ..add(body);
    final all = out.takeBytes();
    final crc = fitCrc(all);
    return Uint8List.fromList([...all, crc & 0xFF, crc >> 8]);
  }
}

const _crcTable = [
  0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, //
  0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
];

/// CRC-16 zoals FIT die gebruikt.
int fitCrc(List<int> bytes) {
  var crc = 0;
  for (final byte in bytes) {
    var tmp = _crcTable[crc & 0xF];
    crc = (crc >> 4) & 0x0FFF;
    crc = crc ^ tmp ^ _crcTable[byte & 0xF];
    tmp = _crcTable[crc & 0xF];
    crc = (crc >> 4) & 0x0FFF;
    crc = crc ^ tmp ^ _crcTable[(byte >> 4) & 0xF];
  }
  return crc;
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ZipEntry {
  ZipEntry(this.name, this.method, this.compressedSize, this.size, this.localOffset);
  final String name;
  final int method;
  final int compressedSize;
  final int size;
  final int localOffset;
}

class ZipFormatException implements Exception {
  ZipFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Eenvoudige zip-lezer die alleen de inhoudsopgave en losse bestanden leest,
/// zodat ook een archief van honderden MB niet in één keer in het geheugen hoeft.
/// Ondersteunt "opgeslagen" en "deflate" (wat Strava en vrijwel alle zips gebruiken) en zip64.
class ZipReader {
  ZipReader._(this._file, this.entries);

  final RandomAccessFile _file;
  final List<ZipEntry> entries;

  static Future<ZipReader> open(String path) async {
    final f = await File(path).open();
    try {
      return ZipReader._(f, await _readDirectory(f));
    } catch (e) {
      await f.close();
      rethrow;
    }
  }

  Future<void> close() => _file.close();

  ZipEntry? find(String name) {
    final n = name.toLowerCase();
    for (final e in entries) {
      if (e.name.toLowerCase() == n) return e;
    }
    // Soms staat alles in een map in de zip.
    for (final e in entries) {
      if (e.name.toLowerCase().endsWith('/$n')) return e;
    }
    return null;
  }

  Future<Uint8List> read(ZipEntry e) async {
    await _file.setPosition(e.localOffset);
    final head = await _file.read(30);
    if (head.length < 30 || _u32(head, 0) != 0x04034b50) throw ZipFormatException('Het archief is beschadigd.');
    final skip = _u16(head, 26) + _u16(head, 28);
    await _file.setPosition(e.localOffset + 30 + skip);
    final raw = await _file.read(e.compressedSize);
    switch (e.method) {
      case 0:
        return raw;
      case 8:
        return Uint8List.fromList(ZLibCodec(raw: true).decode(raw));
      default:
        throw ZipFormatException('Dit archief gebruikt een onbekende compressie.');
    }
  }

  static int _u16(List<int> b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(List<int> b, int o) => _u16(b, o) | (_u16(b, o + 2) << 16);
  static int _u64(List<int> b, int o) => _u32(b, o) + _u32(b, o + 4) * 0x100000000;

  static Future<List<ZipEntry>> _readDirectory(RandomAccessFile f) async {
    final len = await f.length();
    if (len < 22) throw ZipFormatException('Dit is geen zip-bestand.');
    final tailLen = len < 65557 ? len : 65557;
    await f.setPosition(len - tailLen);
    final tail = await f.read(tailLen);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tail[i] == 0x50 && tail[i + 1] == 0x4b && tail[i + 2] == 0x05 && tail[i + 3] == 0x06) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw ZipFormatException('Dit is geen zip-bestand.');
    var count = _u16(tail, eocd + 10);
    var cdSize = _u32(tail, eocd + 12);
    var cdOffset = _u32(tail, eocd + 16);
    if (count == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) {
      // zip64: de echte waarden staan in een extra blok.
      final loc = eocd - 20;
      if (loc < 0 || _u32(tail, loc) != 0x07064b50) throw ZipFormatException('Dit archief kan niet worden gelezen.');
      final z64 = _u64(tail, loc + 8);
      await f.setPosition(z64);
      final rec = await f.read(56);
      if (rec.length < 56 || _u32(rec, 0) != 0x06064b50) throw ZipFormatException('Dit archief kan niet worden gelezen.');
      count = _u64(rec, 32);
      cdSize = _u64(rec, 40);
      cdOffset = _u64(rec, 48);
    }
    await f.setPosition(cdOffset);
    final cd = await f.read(cdSize);
    final out = <ZipEntry>[];
    var p = 0;
    for (var i = 0; i < count && p + 46 <= cd.length; i++) {
      if (_u32(cd, p) != 0x02014b50) break;
      final method = _u16(cd, p + 10);
      var comp = _u32(cd, p + 20);
      var size = _u32(cd, p + 24);
      final nameLen = _u16(cd, p + 28), extraLen = _u16(cd, p + 30), commentLen = _u16(cd, p + 32);
      var offset = _u32(cd, p + 42);
      final name = utf8.decode(cd.sublist(p + 46, p + 46 + nameLen), allowMalformed: true);
      // zip64-velden in het extra blok (alleen de waarden die op 0xFFFFFFFF staan, in deze volgorde).
      var x = p + 46 + nameLen;
      final xEnd = x + extraLen;
      while (x + 4 <= xEnd) {
        final id = _u16(cd, x), sz = _u16(cd, x + 2);
        if (id == 0x0001) {
          var q = x + 4;
          if (size == 0xFFFFFFFF) {
            size = _u64(cd, q);
            q += 8;
          }
          if (comp == 0xFFFFFFFF) {
            comp = _u64(cd, q);
            q += 8;
          }
          if (offset == 0xFFFFFFFF) offset = _u64(cd, q);
        }
        x += 4 + sz;
      }
      if (!name.endsWith('/')) out.add(ZipEntry(name, method, comp, size, offset));
      p += 46 + nameLen + extraLen + commentLen;
    }
    return out;
  }
}

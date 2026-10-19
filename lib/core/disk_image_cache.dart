import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Bewaart kaarttegels en foto's op de telefoon: sneller laden, minder data en
/// (eerder bekeken) kaarten werken ook zonder internet.
class DiskImageCache {
  DiskImageCache._();
  static final instance = DiskImageCache._();

  static const maxBytes = 250 * 1024 * 1024;
  static const maxAge = Duration(days: 30);

  final _client = http.Client();
  Directory? _dir;
  bool _pruned = false;

  Future<Directory> _folder() async {
    final d = _dir ??= Directory('${(await getApplicationCacheDirectory()).path}/images');
    if (!await d.exists()) await d.create(recursive: true);
    if (!_pruned) {
      _pruned = true;
      _prune(d).ignore();
    }
    return d;
  }

  /// Vaste korte bestandsnaam (FNV-1a, 64 bits als twee helften).
  static String fileName(String key) {
    var a = 0x811c9dc5, b = 0x01000193;
    for (final c in key.codeUnits) {
      a = ((a ^ c) * 0x01000193) & 0xffffffff;
      b = ((b ^ c) * 0x0100019d) & 0xffffffff;
    }
    return '${a.toRadixString(16)}${b.toRadixString(16)}.img';
  }

  Future<Uint8List> load(String url, {String? key, Map<String, String>? headers}) async {
    final f = File('${(await _folder()).path}/${fileName(key ?? url)}');
    try {
      if (await f.exists() && DateTime.now().difference(await f.lastModified()) < maxAge) {
        return await f.readAsBytes();
      }
    } catch (_) {}
    try {
      final res = await _client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) throw HttpException('HTTP ${res.statusCode}');
      f.writeAsBytes(res.bodyBytes, flush: false).ignore();
      return res.bodyBytes;
    } catch (e) {
      // Geen internet: dan een oudere versie als die er is.
      if (await f.exists()) return f.readAsBytes();
      rethrow;
    }
  }

  /// Oudste bestanden weg als de map te groot wordt.
  Future<void> _prune(Directory d) async {
    try {
      final files = await d.list().where((e) => e is File).cast<File>().toList();
      final stats = <(File, FileStat)>[];
      var total = 0;
      for (final f in files) {
        final s = await f.stat();
        stats.add((f, s));
        total += s.size;
      }
      if (total <= maxBytes) return;
      stats.sort((x, y) => x.$2.modified.compareTo(y.$2.modified));
      for (final (f, s) in stats) {
        if (total <= maxBytes * 0.8) break;
        await f.delete();
        total -= s.size;
      }
    } catch (_) {}
  }

  /// Alles wissen (bij uitloggen).
  Future<void> clear() async {
    try {
      final d = await _folder();
      await d.delete(recursive: true);
      _dir = null;
    } catch (_) {}
  }
}

/// Afbeelding via de schijfcache. [cacheKey] voor URL's die steeds anders zijn (ondertekende links).
@immutable
class CachedNetImage extends ImageProvider<CachedNetImage> {
  const CachedNetImage(this.url, {this.cacheKey, this.headers});
  final String url;
  final String? cacheKey;
  final Map<String, String>? headers;

  String get _key => cacheKey ?? url;

  @override
  Future<CachedNetImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedNetImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await DiskImageCache.instance.load(url, key: _key, headers: headers);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is CachedNetImage && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}

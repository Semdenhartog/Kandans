import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/disk_image_cache.dart';
import '../../core/error_reporter.dart';
import '../../domain/geo.dart';
import '../../domain/map_tiles.dart';

/// Een route waarvan de kaart op de telefoon staat, zodat hij ook zonder internet te zien is.
class OfflinePack {
  const OfflinePack({required this.id, required this.name, required this.tiles, required this.bytes, required this.savedAt, required this.files});
  final String id;
  final String name;
  final int tiles;
  final int bytes;
  final DateTime savedAt;

  /// Bestandsnamen van de tegels (om ze later weer te kunnen weghalen).
  final List<String> files;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'tiles': tiles, 'bytes': bytes, 'at': savedAt.toIso8601String(), 'files': files};

  static OfflinePack? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return OfflinePack(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        tiles: (j['tiles'] as num).toInt(),
        bytes: (j['bytes'] as num).toInt(),
        savedAt: DateTime.parse(j['at'] as String),
        files: [for (final f in (j['files'] as List)) f as String],
      );
    } catch (_) {
      return null;
    }
  }
}

/// Zeg "stop" tegen een lopende download.
class OfflineCancel {
  bool cancelled = false;
}

/// Kaarten van routes op de telefoon bewaren. De lijst staat in `packs.json` naast de tegels,
/// zodat uitloggen (waarbij die map wordt gewist) ook de lijst opruimt.
class OfflineMaps {
  OfflineMaps._();
  static final instance = OfflineMaps._();

  static const _template = pdokGreyTiles;

  Future<File> _manifest() async => File('${(await DiskImageCache.instance.offlineFolder()).path}/packs.json');

  Future<Map<String, OfflinePack>> packs() async {
    try {
      final f = await _manifest();
      if (!await f.exists()) return {};
      final j = jsonDecode(await f.readAsString());
      if (j is! List) return {};
      return {
        for (final p in j.map(OfflinePack.fromJson).whereType<OfflinePack>()) p.id: p,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(Map<String, OfflinePack> all) async {
    final f = await _manifest();
    await f.writeAsString(jsonEncode([for (final p in all.values) p.toJson()]), flush: true);
  }

  Future<OfflinePack?> pack(String id) async => (await packs())[id];

  /// Bewaart de kaart langs [track]. [onProgress] krijgt (klaar, totaal). Gooit een fout als te veel tegels mislukken.
  /// Bij annuleren blijft er niets staan van deze download.
  Future<OfflinePack?> download({
    required String id,
    required String name,
    required List<LatLng> track,
    required TilePlan plan,
    void Function(int done, int total)? onProgress,
    OfflineCancel? cancel,
    int workers = 4,
  }) async {
    final queue = List<TileId>.of(plan.tiles);
    final total = queue.length;
    final names = <String>{};
    var bytes = 0, done = 0, failed = 0;

    Future<void> worker() async {
      while (queue.isNotEmpty && !(cancel?.cancelled ?? false)) {
        final t = queue.removeLast();
        try {
          final r = await DiskImageCache.instance.pin(tileUrl(_template, t));
          if (r.bytes > 0) {
            names.add(r.name);
            bytes += r.bytes;
          }
        } catch (_) {
          failed++;
        }
        onProgress?.call(++done, total);
      }
    }

    await Future.wait([for (var i = 0; i < workers; i++) worker()]);

    if (cancel?.cancelled ?? false) {
      await _dropUnshared(names, keepFor: id);
      return null;
    }
    if (failed > total * 0.1) {
      await _dropUnshared(names, keepFor: id);
      throw const HttpException('Te veel kaartdelen konden niet worden opgehaald.');
    }
    final all = await packs();
    all[id] = OfflinePack(id: id, name: name, tiles: names.length, bytes: bytes, savedAt: DateTime.now(), files: names.toList());
    await _write(all);
    return all[id];
  }

  /// Haalt de kaart van een route weg. Tegels die ook bij een andere route horen blijven staan.
  Future<void> remove(String id) async {
    final all = await packs();
    final p = all.remove(id);
    if (p == null) return;
    await _dropUnshared(p.files.toSet(), keepFor: id, others: all);
    await _write(all);
  }

  Future<void> _dropUnshared(Set<String> names, {required String keepFor, Map<String, OfflinePack>? others}) async {
    try {
      final all = others ?? await packs();
      final shared = <String>{
        for (final p in all.values)
          if (p.id != keepFor) ...p.files,
      };
      await DiskImageCache.instance.unpin(names.where((n) => !shared.contains(n)));
    } catch (kErr, kSt) {
      ErrorReporter.report(kErr, kSt, context: 'offline_maps.dart');
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/core/disk_image_cache.dart';
import 'package:runwise/domain/geo.dart';
import 'package:runwise/domain/map_tiles.dart';

void main() {
  test('tegelnummers kloppen (Amsterdam)', () {
    expect((tileX(4.9041, 10), tileY(52.3676, 10)), (525, 336));
    expect((tileX(4.9041, 13), tileY(52.3676, 13)), (4207, 2692));
    expect((tileX(4.9041, 17), tileY(52.3676, 17)), (67321, 43076));
  });

  test('tegeladres is gelijk aan wat de kaart zelf vraagt', () {
    expect(tileUrl(pdokGreyTiles, const TileId(16, 33660, 21538)),
        'https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/grijs/EPSG:3857/16/33660/21538.png');
  });

  // Een rechte route van ± 5 km naar het oosten, door het Amsterdamse Bos-gebied.
  final track = [for (var i = 0; i <= 50; i++) LatLng(52.3200, 4.8300 + i * 0.0011)];

  test('plan: alle zoomniveaus, beginpunt en eindpunt zitten erin', () {
    final plan = tilePlanForTrack(track)!;
    expect(plan.maxZoom, 17);
    final set = plan.tiles.toSet();
    for (var z = 13; z <= 17; z++) {
      for (final p in [track.first, track.last, track[25]]) {
        expect(set.contains(TileId(z, tileX(p.lon, z), tileY(p.lat, z))), isTrue, reason: 'zoom $z');
      }
    }
    expect(plan.tiles.length, greaterThan(150));
    expect(plan.tiles.length, lessThan(1500));
    expect(estimateTileBytes(plan.tiles.length), lessThan(30 * 1024 * 1024));
  });

  test('geen gaten midden in de route op het hoogste zoomniveau', () {
    final set = tilePlanForTrack(track)!.tiles.toSet();
    for (var i = 0; i < track.length; i++) {
      final p = track[i];
      expect(set.contains(TileId(17, tileX(p.lon, 17), tileY(p.lat, 17))), isTrue, reason: 'punt $i');
    }
  });

  test('te veel tegels: hoogste zoom valt weg, of null', () {
    final small = tilePlanForTrack(track, maxTiles: 100)!;
    expect(small.maxZoom, lessThan(17));
    expect(small.tiles.length, lessThanOrEqualTo(100));
    expect(tilePlanForTrack(track, maxTiles: 3), isNull);
    expect(tilePlanForTrack([track.first]), isNull);
  });

  test('alleen Nederland', () {
    expect(inNetherlands(const LatLng(52.37, 4.9)), isTrue);
    expect(inNetherlands(const LatLng(48.85, 2.35)), isFalse);
  });

  test('bestandsnaam van een tegel is stabiel', () {
    final u = tileUrl(pdokGreyTiles, const TileId(15, 16830, 10769));
    expect(DiskImageCache.fileName(u), DiskImageCache.fileName(u));
    expect(DiskImageCache.fileName(u), isNot(DiskImageCache.fileName(tileUrl(pdokGreyTiles, const TileId(15, 16831, 10769)))));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/models/models.dart';
import 'package:runwise/domain/shoe_shop.dart';

void main() {
  group('schoenenwinkel', () {
    test('zonder instelling: gewone zoeklink, geen partner', () {
      final s = ShoeShop.fromConfig(const {});
      expect(s.isFallback, isTrue);
      expect(s.isPartner, isFalse);
      expect(s.urlFor('Novablast 4').toString(), 'https://www.google.com/search?q=Novablast+4+hardloopschoenen');
    });

    test('ingestelde partnerwinkel', () {
      final s = ShoeShop.fromConfig(const {
        'shoe_shop_name': 'Hardloopwinkel',
        'shoe_shop_url': 'https://winkel.example/zoek?q={q}&ref=runwise',
        'shoe_shop_partner': 'true',
      });
      expect(s.isFallback, isFalse);
      expect(s.isPartner, isTrue);
      expect(s.urlFor('Gel-Nimbus 26').toString(), 'https://winkel.example/zoek?q=Gel-Nimbus+26&ref=runwise');
    });

    test('onveilige of onvolledige link wordt niet gebruikt', () {
      expect(ShoeShop.fromConfig(const {'shoe_shop_name': 'X', 'shoe_shop_url': 'http://x.example/?q={q}'}).isFallback, isTrue);
      expect(ShoeShop.fromConfig(const {'shoe_shop_name': 'X', 'shoe_shop_url': 'https://x.example/'}).isFallback, isTrue);
    });

    test('welke schoen eerst vervangen moet worden', () {
      final now = DateTime(2026, 1, 1);
      final a = Shoe(id: 'a', name: 'A', startKm: 640, limitKm: 700, createdAt: now);
      final b = Shoe(id: 'b', name: 'B', startKm: 700, limitKm: 700, createdAt: now);
      final c = Shoe(id: 'c', name: 'C', startKm: 100, limitKm: 700, createdAt: now);
      final old = Shoe(id: 'd', name: 'D', startKm: 900, limitKm: 700, retired: true, createdAt: now);
      expect(shoeToReplace([a, b, c, old], const [])!.shoe.name, 'B');
      expect(shoeToReplace([c, old], const []), isNull);
    });
  });
}

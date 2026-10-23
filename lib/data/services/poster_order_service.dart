import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';

/// Een posterformaat met prijs (uit de tabel poster_products; de server rekent zelf ook).
class PosterProduct {
  const PosterProduct({
    required this.id,
    required this.label,
    required this.widthMm,
    required this.heightMm,
    required this.priceCents,
    this.description,
  });

  final String id;
  final String label;
  final int widthMm;
  final int heightMm;
  final int priceCents;
  final String? description;

  double get aspect => widthMm / heightMm;

  /// "€ 24,95"
  String get priceLabel => '€ ${(priceCents / 100).toStringAsFixed(2).replaceAll('.', ',')}';

  factory PosterProduct.fromJson(Map<String, dynamic> j) => PosterProduct(
        id: j['id'] as String,
        label: j['label'] as String,
        widthMm: (j['width_mm'] as num).toInt(),
        heightMm: (j['height_mm'] as num).toInt(),
        priceCents: (j['price_cents'] as num).toInt(),
        description: j['description'] as String?,
      );
}

/// Breedte in pixels van het drukbestand: zo scherp mogelijk (tot 300 dpi), maar hooguit
/// [maxPixels] in totaal, zodat een telefoon het geheugen aankan (50×70 cm wordt ±155 dpi).
int printWidthPx(PosterProduct p, {int maxPixels = 13000000}) {
  final wIn = p.widthMm / 25.4, hIn = p.heightMm / 25.4;
  final dpi = math.min(300.0, math.sqrt(maxPixels / (wIn * hIn)));
  return (wIn * dpi).floor();
}

/// Adres voor de bezorging.
class ShippingAddress {
  const ShippingAddress({
    required this.name,
    required this.street,
    required this.houseNumber,
    required this.postcode,
    required this.city,
    required this.country,
    required this.email,
  });

  final String name, street, houseNumber, postcode, city, country, email;

  Map<String, String> toJson() => {
        'name': name.trim(),
        'street': street.trim(),
        'house_number': houseNumber.trim(),
        'postcode': postcode.trim().toUpperCase(),
        'city': city.trim(),
        'country': country,
        'email': email.trim(),
      };

  static ShippingAddress? fromJson(Object? j) {
    if (j is! Map) return null;
    String s(String k) => (j[k] ?? '').toString();
    return ShippingAddress(
      name: s('name'),
      street: s('street'),
      houseNumber: s('house_number'),
      postcode: s('postcode'),
      city: s('city'),
      country: s('country').isEmpty ? 'NL' : s('country'),
      email: s('email'),
    );
  }
}

/// Status van een bestelling zoals de klant hem ziet.
enum PosterOrderStatus {
  nieuw('Wacht op betaling'),
  betaald('Betaald, wordt klaargezet'),
  concept('Klaargezet (testmodus, wordt niet gedrukt)'),
  inProductie('Wordt gedrukt'),
  verzonden('Onderweg naar je toe'),
  geannuleerd('Geannuleerd'),
  mislukt('Er ging iets mis. We nemen contact met je op.');

  const PosterOrderStatus(this.label);
  final String label;

  static PosterOrderStatus parse(String? s) => switch (s) {
        'betaald' => betaald,
        'concept' => concept,
        'in_productie' => inProductie,
        'verzonden' => verzonden,
        'geannuleerd' => geannuleerd,
        'mislukt' => mislukt,
        _ => nieuw,
      };
}

class PosterOrder {
  const PosterOrder({
    required this.id,
    required this.title,
    required this.productId,
    required this.priceCents,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String productId;
  final int priceCents;
  final PosterOrderStatus status;
  final DateTime createdAt;

  factory PosterOrder.fromJson(Map<String, dynamic> j) => PosterOrder(
        id: j['id'] as String,
        title: j['title'] as String,
        productId: j['product_id'] as String,
        priceCents: (j['price_cents'] as num).toInt(),
        status: PosterOrderStatus.parse(j['status'] as String?),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class PosterOrderService {
  PosterOrderService(this._db);
  final SupabaseClient _db;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw Exception('Je bent niet ingelogd.');
    return id;
  }

  Future<List<PosterProduct>> products() async {
    final rows = await _db.from('poster_products').select().eq('active', true).order('sort');
    return [for (final r in rows) PosterProduct.fromJson(r)];
  }

  Future<List<PosterOrder>> orders() async {
    final rows = await _db
        .from('poster_orders')
        .select('id, title, product_id, price_cents, status, created_at')
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .limit(50);
    return [for (final r in rows) PosterOrder.fromJson(r)];
  }

  /// Zet het drukbestand klaar (privé map van de gebruiker) en geeft het pad terug.
  Future<String> uploadPrintFile(Uint8List png) async {
    final path = '$_uid/${DateTime.now().millisecondsSinceEpoch}.png';
    await _db.storage.from('poster-files').uploadBinary(
          path,
          png,
          fileOptions: const FileOptions(contentType: 'image/png', upsert: false),
        );
    return path;
  }

  /// Maakt de bestelling aan; geeft het adres van de betaalpagina terug.
  Future<({String orderId, Uri checkoutUrl})> order({
    required PosterProduct product,
    required String title,
    required String style,
    required String filePath,
    required ShippingAddress address,
  }) async {
    try {
      final res = await _db.functions.invoke('poster-order', body: {
        'product_id': product.id,
        'title': title,
        'style': style,
        'file_path': filePath,
        'shipping': address.toJson(),
      });
      final m = (res.data as Map).cast<String, dynamic>();
      return (orderId: m['order_id'] as String, checkoutUrl: Uri.parse(m['checkout_url'] as String));
    } on FunctionException catch (e) {
      final details = e.details is Map ? (e.details as Map).cast<String, dynamic>() : <String, dynamic>{};
      throw Exception(details['error'] ?? 'Bestellen is niet gelukt. Probeer het later opnieuw.');
    }
  }
}

final posterOrderServiceProvider = Provider<PosterOrderService>((ref) => PosterOrderService(ref.watch(supabaseProvider)));

final posterProductsProvider = FutureProvider<List<PosterProduct>>((ref) => ref.watch(posterOrderServiceProvider).products());

final posterOrdersProvider = FutureProvider<List<PosterOrder>>((ref) => ref.watch(posterOrderServiceProvider).orders());

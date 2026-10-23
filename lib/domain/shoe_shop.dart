import '../data/models/models.dart';
import 'shoes.dart';

/// De winkel waar "Bekijk nieuwe schoenen" naartoe gaat.
///
/// Instelbaar in Supabase (tabel model_config), zodat Sem zelf de partnerlink van een
/// hardloopspeciaalzaak kan invullen zonder nieuwe app-versie:
///   shoe_shop_name     bijv. "Runnersworld"
///   shoe_shop_url      bijv. "https://…/zoeken?q={q}&partner=…"  ({q} = schoenmodel)
///   shoe_shop_partner  "true" als het een partnerlink is (dan staat dat er eerlijk bij)
class ShoeShop {
  const ShoeShop({required this.name, required this.urlTemplate, this.isPartner = false});

  final String name;
  final String urlTemplate;

  /// Verdient RunWise iets aan een aankoop via deze link? Dan melden we dat.
  final bool isPartner;

  /// Zolang er geen winkel is ingesteld: gewoon zoeken op het web, zonder partner.
  static const fallback = ShoeShop(name: '', urlTemplate: 'https://www.google.com/search?q={q}+hardloopschoenen');

  bool get isFallback => name.isEmpty;

  /// Link voor dit schoenmodel.
  Uri urlFor(String shoeName) =>
      Uri.parse(urlTemplate.replaceAll('{q}', Uri.encodeQueryComponent(shoeName.trim())));

  /// Uit de instellingen in Supabase. Alleen https-links met {q}; anders [fallback].
  static ShoeShop fromConfig(Map<String, String> c) {
    final name = (c['shoe_shop_name'] ?? '').trim();
    final url = (c['shoe_shop_url'] ?? '').trim();
    if (name.isEmpty || !url.startsWith('https://') || !url.contains('{q}')) return fallback;
    return ShoeShop(name: name, urlTemplate: url, isPartner: (c['shoe_shop_partner'] ?? '').trim().toLowerCase() == 'true');
  }
}

/// Schoen die het eerst vervangen moet worden (verst over de 90% van zijn grens), of null.
({Shoe shoe, double km})? shoeToReplace(List<Shoe> shoes, List<Activity> runs) {
  ({Shoe shoe, double km})? best;
  for (final s in shoes) {
    if (s.retired || s.id == null || !shoeWornOut(s, runs)) continue;
    final km = shoeKm(s, runs);
    if (best == null || km / s.limitKm > best.km / best.shoe.limitKm) best = (shoe: s, km: km);
  }
  return best;
}

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/config.dart';

/// Een abonnementsoptie zoals de paywall hem toont.
class PlanOption {
  PlanOption({
    required this.package,
    required this.isYearly,
    required this.price,
    required this.hasFreeTrial,
  });

  final Package package;
  final bool isYearly;
  final String price;
  final bool hasFreeTrial;
}

/// Abonnementen via RevenueCat (die regelt de betaling via Google Play).
///
/// De RevenueCat-gebruiker is dezelfde id als in Supabase, zodat de
/// webhook het abonnement bij het juiste account kan zetten.
class BillingService {
  String? _configuredFor;

  bool get isAvailable => AppConfig.billingConfigured;

  Future<void> _ensure(String userId) async {
    if (!isAvailable) throw Exception('Abonnementen zijn nog niet beschikbaar.');
    if (_configuredFor == null) {
      await Purchases.configure(
        PurchasesConfiguration(AppConfig.revenueCatAndroidKey)..appUserID = userId,
      );
      _configuredFor = userId;
    } else if (_configuredFor != userId) {
      await Purchases.logIn(userId);
      _configuredFor = userId;
    }
  }

  /// Maand- en jaarabonnement uit de "current offering" in RevenueCat.
  Future<List<PlanOption>> plans(String userId) async {
    await _ensure(userId);
    final offering = (await Purchases.getOfferings()).current;
    if (offering == null) return const [];
    final result = <PlanOption>[];
    for (final p in [offering.monthly, offering.annual]) {
      if (p == null) continue;
      final intro = p.storeProduct.introductoryPrice;
      result.add(PlanOption(
        package: p,
        isYearly: p.packageType == PackageType.annual,
        price: p.storeProduct.priceString,
        hasFreeTrial: intro != null && intro.price == 0,
      ));
    }
    return result;
  }

  /// Koopt het abonnement. Geeft false als de gebruiker zelf annuleert.
  Future<bool> buy(String userId, PlanOption plan) async {
    await _ensure(userId);
    try {
      await Purchases.purchasePackage(plan.package);
      return true;
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      throw Exception('Betalen is niet gelukt. Probeer het opnieuw.');
    }
  }

  // ------------------------------------------------------------ Luxe-ontwerpen (eenmalige aankoop)

  /// Product in Google Play en RevenueCat (eenmalig, niet verbruikbaar).
  static const luxeProductId = 'runwise_luxe_designs';

  /// Rechten-id in RevenueCat die bij het product hoort.
  static const luxeEntitlement = 'luxe_designs';

  Future<StoreProduct?> _luxeProduct() async {
    final list = await Purchases.getProducts([luxeProductId], productCategory: ProductCategory.nonSubscription);
    return list.isEmpty ? null : list.first;
  }

  /// Prijs zoals Google Play hem toont (bijv. "€ 2,99"), of null als het product nog niet bestaat.
  Future<String?> luxePrice(String userId) async {
    await _ensure(userId);
    return (await _luxeProduct())?.priceString;
  }

  /// Heeft deze gebruiker de Luxe-ontwerpen gekocht?
  Future<bool> hasLuxeDesigns(String userId) async {
    await _ensure(userId);
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.containsKey(luxeEntitlement);
  }

  /// Koopt de Luxe-ontwerpen. Geeft false als de gebruiker zelf annuleert.
  Future<bool> buyLuxeDesigns(String userId) async {
    await _ensure(userId);
    final product = await _luxeProduct();
    if (product == null) throw Exception('De Luxe-ontwerpen zijn nog niet te koop. Probeer het later opnieuw.');
    try {
      await Purchases.purchaseStoreProduct(product);
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) return false;
      throw Exception('Betalen is niet gelukt. Probeer het opnieuw.');
    }
    return hasLuxeDesigns(userId);
  }

  /// Zet een eerder gekocht abonnement terug (bijv. na opnieuw installeren).
  Future<bool> restore(String userId) async {
    await _ensure(userId);
    final info = await Purchases.restorePurchases();
    return info.entitlements.active.isNotEmpty;
  }
}

final billingServiceProvider = Provider<BillingService>((ref) => BillingService());

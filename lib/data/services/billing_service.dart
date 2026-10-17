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

  /// Zet een eerder gekocht abonnement terug (bijv. na opnieuw installeren).
  Future<bool> restore(String userId) async {
    await _ensure(userId);
    final info = await Purchases.restorePurchases();
    return info.entitlements.active.isNotEmpty;
  }
}

final billingServiceProvider = Provider<BillingService>((ref) => BillingService());

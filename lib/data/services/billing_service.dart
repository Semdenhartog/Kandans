import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/supabase.dart';

/// Begrijpelijke foutmelding bij betalen (de tekst is al vertaald).
class BillingException implements Exception {
  const BillingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Uitkomst van de paywall.
enum PaywallOutcome { purchased, restored, closed, alreadyPremium }

/// Betalen via RevenueCat (die regelt de betaling via Google Play).
///
/// - Premium = het recht [premiumEntitlement] (`kadans_pro`), met de producten
///   `monthly`, `yearly` en `lifetime` in de offering "default".
/// - De RevenueCat-gebruiker is dezelfde id als in Supabase, zodat de webhook
///   het abonnement bij het juiste account zet. De server (profiles.is_premium)
///   blijft leidend voor de coach; de app kijkt daarnaast live naar RevenueCat.
class BillingService {
  BillingService() : _key = AppConfig.revenueCatAndroidKey;

  /// Voor tests: een andere sleutel gebruiken.
  @visibleForTesting
  BillingService.withKey(this._key);

  final String _key;

  /// Recht in RevenueCat dat Premium geeft.
  static const premiumEntitlement = 'kadans_pro';

  /// Eenmalig product voor de Luxe-ontwerpen (los van Premium).
  static const luxeProductId = 'runwise_luxe_designs';
  static const luxeEntitlement = 'luxe_designs';

  String? _configuredFor;
  Future<void> _queue = Future.value();
  final _infoController = StreamController<CustomerInfo>.broadcast();

  /// Sleutel van RevenueCat's Test Store (nep-aankopen, alleen om te testen).
  bool get isTestStoreKey => _key.startsWith('test_');

  /// Met een Test Store-sleutel laat RevenueCat een release-build bewust crashen.
  /// Daarom: in een release-build met zo'n sleutel doen we alsof betalen nog niet kan.
  bool get isAvailable => _key.isNotEmpty && !(isTestStoreKey && kReleaseMode);

  /// Elke wijziging in aankopen (kopen, verlengen, verlopen, terugzetten).
  Stream<CustomerInfo> get customerInfoStream => _infoController.stream;

  /// Zorgt dat RevenueCat klaarstaat voor deze gebruiker. Altijd één tegelijk,
  /// zodat twee schermen niet tegelijk `configure` aanroepen.
  Future<void> _ensure(String userId) {
    final next = _queue.then((_) => _configure(userId));
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _configure(String userId) async {
    if (!isAvailable) throw BillingException(tr('Abonnementen zijn nog niet beschikbaar.'));
    if (_configuredFor == userId) return;
    await _guard(() async {
      if (_configuredFor == null) {
        await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
        await Purchases.configure(PurchasesConfiguration(_key)..appUserID = userId);
        Purchases.addCustomerInfoUpdateListener(_infoController.add);
      } else {
        await Purchases.logIn(userId);
      }
    });
    _configuredFor = userId;
  }

  /// Voert een RevenueCat-aanroep uit en vertaalt fouten naar gewone taal.
  /// Geeft `null` terug als de gebruiker zelf annuleert.
  Future<T?> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return null;
      debugPrint('RevenueCat: $code ${e.message}');
      throw BillingException(_message(code));
    }
  }

  static String _message(PurchasesErrorCode code) => switch (code) {
        PurchasesErrorCode.networkError ||
        PurchasesErrorCode.offlineConnectionError =>
          tr('Geen internetverbinding. Controleer je verbinding en probeer het opnieuw.'),
        PurchasesErrorCode.purchaseNotAllowedError =>
          tr('Aankopen zijn niet toegestaan op dit toestel of Google-account.'),
        PurchasesErrorCode.paymentPendingError =>
          tr('Je betaling wacht nog op goedkeuring. Premium start zodra die rond is.'),
        PurchasesErrorCode.productAlreadyPurchasedError =>
          tr('Je hebt dit al gekocht. Tik op "Aankoop terugzetten".'),
        PurchasesErrorCode.productNotAvailableForPurchaseError =>
          tr('Dit is nu niet te koop. Probeer het later opnieuw.'),
        PurchasesErrorCode.operationAlreadyInProgressError => tr('Er loopt al een aankoop. Even geduld.'),
        PurchasesErrorCode.storeProblemError => tr('Google Play gaf een fout. Probeer het later opnieuw.'),
        PurchasesErrorCode.configurationError ||
        PurchasesErrorCode.invalidCredentialsError =>
          tr('Abonnementen zijn nog niet goed ingesteld. Probeer het later opnieuw.'),
        _ => tr('Betalen is niet gelukt. Probeer het opnieuw.'),
      };

  // ------------------------------------------------------------ Premium

  /// Heeft deze klant Premium volgens RevenueCat?
  static bool hasPremium(CustomerInfo info) => info.entitlements.active[premiumEntitlement]?.isActive ?? false;

  /// Actuele klantgegevens (RevenueCat bewaart ze ook offline).
  Future<CustomerInfo> customerInfo(String userId) async {
    await _ensure(userId);
    return (await _guard(Purchases.getCustomerInfo))!;
  }

  /// Toont de paywall uit het RevenueCat-dashboard (maand, jaar en lifetime),
  /// maar alleen als de gebruiker nog geen Premium heeft.
  Future<PaywallOutcome> presentPaywall(String userId) async {
    await _ensure(userId);
    final result = await _guard(
      () => RevenueCatUI.presentPaywallIfNeeded(premiumEntitlement, displayCloseButton: true),
    );
    return switch (result) {
      PaywallResult.purchased => PaywallOutcome.purchased,
      PaywallResult.restored => PaywallOutcome.restored,
      PaywallResult.notPresented => PaywallOutcome.alreadyPremium,
      PaywallResult.error => throw BillingException(tr('De abonnementen konden niet worden geladen. Probeer het later opnieuw.')),
      PaywallResult.cancelled || null => PaywallOutcome.closed,
    };
  }

  /// Customer Center: abonnement bekijken, wijzigen, opzeggen of terugzetten.
  Future<void> presentCustomerCenter(String userId, {VoidCallback? onRestored}) async {
    await _ensure(userId);
    await _guard(() => RevenueCatUI.presentCustomerCenter(
          onRestoreCompleted: (_) => onRestored?.call(),
        ));
  }

  /// Zet eerdere aankopen terug (bijv. na opnieuw installeren). True als er iets actiefs is.
  Future<bool> restore(String userId) async {
    await _ensure(userId);
    final info = await _guard(Purchases.restorePurchases);
    return info?.entitlements.active.isNotEmpty ?? false;
  }

  // ------------------------------------------------------------ Luxe-ontwerpen (eenmalige aankoop)

  Future<StoreProduct?> _luxeProduct() async {
    final list = await _guard(
      () => Purchases.getProducts([luxeProductId], productCategory: ProductCategory.nonSubscription),
    );
    return (list == null || list.isEmpty) ? null : list.first;
  }

  /// Prijs zoals Google Play hem toont (bijv. "€ 2,99"), of null als het product nog niet bestaat.
  Future<String?> luxePrice(String userId) async {
    await _ensure(userId);
    return (await _luxeProduct())?.priceString;
  }

  /// Heeft deze gebruiker de Luxe-ontwerpen gekocht?
  Future<bool> hasLuxeDesigns(String userId) async {
    final info = await customerInfo(userId);
    return info.entitlements.active.containsKey(luxeEntitlement);
  }

  /// Koopt de Luxe-ontwerpen. Geeft false als de gebruiker zelf annuleert.
  Future<bool> buyLuxeDesigns(String userId) async {
    await _ensure(userId);
    final product = await _luxeProduct();
    if (product == null) throw BillingException(tr('De Luxe-ontwerpen zijn nog niet te koop. Probeer het later opnieuw.'));
    final result = await _guard(() => Purchases.purchase(PurchaseParams.storeProduct(product)));
    if (result == null) return false;
    return result.customerInfo.entitlements.active.containsKey(luxeEntitlement);
  }

  void dispose() {
    if (_configuredFor != null) Purchases.removeCustomerInfoUpdateListener(_infoController.add);
    _infoController.close();
  }
}

final billingServiceProvider = Provider<BillingService>((ref) {
  final service = BillingService();
  ref.onDispose(service.dispose);
  return service;
});

/// Live: heeft de ingelogde gebruiker Premium volgens RevenueCat?
/// Werkt direct na een aankoop, nog vóór de server het via de webhook weet.
final revenueCatPremiumProvider = StreamProvider.autoDispose<bool>((ref) async* {
  final billing = ref.watch(billingServiceProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null || !billing.isAvailable) {
    yield false;
    return;
  }
  yield BillingService.hasPremium(await billing.customerInfo(user.id));
  yield* billing.customerInfoStream.map(BillingService.hasPremium);
});

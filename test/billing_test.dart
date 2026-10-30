import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/data/services/billing_service.dart';

void main() {
  test('zonder sleutel kan betalen niet', () {
    final b = BillingService.withKey('');
    expect(b.isAvailable, isFalse);
    expect(b.isTestStoreKey, isFalse);
  });

  test('Test Store-sleutel wordt herkend en alleen buiten release gebruikt', () {
    final b = BillingService.withKey('test_abc');
    expect(b.isTestStoreKey, isTrue);
    expect(b.isAvailable, !kReleaseMode);
  });

  test('Google Play-sleutel werkt altijd', () {
    final b = BillingService.withKey('goog_abc');
    expect(b.isTestStoreKey, isFalse);
    expect(b.isAvailable, isTrue);
  });

  test('Premium-recht heet kadans_pro', () {
    expect(BillingService.premiumEntitlement, 'kadans_pro');
  });
}

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App vergrendelen met vingerafdruk of gezicht (of anders de pincode van je telefoon).
/// Je blijft gewoon ingelogd; bij openen bevestig je alleen dat jij het bent.
class AppLockService {
  AppLockService._();
  static final instance = AppLockService._();

  static const _key = 'app_lock_biometric';

  /// Na zo lang op de achtergrond vragen we opnieuw om je vingerafdruk.
  static const relockAfter = Duration(minutes: 5);

  final _auth = LocalAuthentication();
  final enabled = ValueNotifier<bool>(false);

  /// True zolang de app op slot zit.
  final locked = ValueNotifier<bool>(false);
  DateTime? _pausedAt;

  /// Net met je wachtwoord ingelogd: één keer aanbieden om de vingerafdruk aan te zetten.
  bool offerAfterLogin = false;
  bool _busy = false;

  /// Bij het starten: lezen of de vergrendeling aan staat (en dan meteen op slot).
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled.value = p.getBool(_key) ?? false;
      locked.value = enabled.value;
    } catch (_) {}
  }

  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && (await _auth.canCheckBiometrics || (await _auth.getAvailableBiometrics()).isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// Vraagt om je vingerafdruk. Pincode of patroon van je telefoon mag ook (dan kom je er altijd in).
  Future<bool> authenticate({String reason = 'Ontgrendel RunWise'}) async {
    if (_busy) return false;
    _busy = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
    } catch (_) {
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<bool> setEnabled(bool on) async {
    if (on && !await authenticate(reason: 'Bevestig met je vingerafdruk')) return false;
    enabled.value = on;
    if (!on) locked.value = false;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, on);
    } catch (_) {}
    return true;
  }

  Future<void> unlock() async {
    if (await authenticate()) locked.value = false;
  }

  void onPaused() => _pausedAt = DateTime.now();

  /// Terug in de app: na [relockAfter] weer op slot (niet tijdens een run).
  void onResumed({bool recording = false}) {
    final at = _pausedAt;
    _pausedAt = null;
    if (!enabled.value || recording || at == null) return;
    if (DateTime.now().difference(at) >= relockAfter) locked.value = true;
  }

  /// Bij uitloggen: niets meer op slot.
  void reset() => locked.value = false;
}

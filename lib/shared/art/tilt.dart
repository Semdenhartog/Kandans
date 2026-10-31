import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Hoe schuin je de telefoon houdt (-1..1 per as), zacht uitgemiddeld.
/// Eén luisteraar voor de hele app; de sensor staat alleen aan zolang iets kijkt.
class Tilt extends ValueNotifier<Offset> {
  Tilt._() : super(Offset.zero);
  static final instance = Tilt._();

  StreamSubscription<AccelerometerEvent>? _sub;
  int _users = 0;

  static bool get _supported {
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _users++;
    if (_users == 1) _start();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _users = (_users - 1).clamp(0, 1 << 20);
    if (_users == 0) _stop();
  }

  void _start() {
    if (!_supported || _sub != null) return;
    if (WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) return;
    try {
      _sub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
        // Rechtop gehouden ligt y rond 9,8 en x rond 0.
        final tx = (e.x / -4).clamp(-1.0, 1.0);
        final ty = ((e.y - 6.5) / 4).clamp(-1.0, 1.0);
        final next = Offset(value.dx * 0.85 + tx * 0.15, value.dy * 0.85 + ty * 0.15);
        if ((next - value).distance > 0.004) value = next;
      }, onError: (Object _) {});
    } catch (_) {}
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
  }
}

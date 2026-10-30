import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/stride_sensor.dart';
import 'heart_rate_service.dart';

/// Loopsensor via Bluetooth (voetsensor zoals Stryd of Polar Stride): cadans en snelheid.
/// Werkt ook mee met een hartslagband die dezelfde dienst heeft (bijv. Wahoo Tickr X):
/// die meldt zich via [HeartRateService] aan op [onPayload].
class StrideSensorService {
  StrideSensorService._();
  static final instance = StrideSensorService._();

  static final service = Uuid.parse('1814');
  static final measurement = Uuid.parse('2A53');
  static const _idKey = 'stride_device_id';
  static const _nameKey = 'stride_device_name';

  final _ble = FlutterReactiveBle();

  /// Stappen per minuut (null = geen sensor of geen signaal).
  final cadence = ValueNotifier<int?>(null);

  /// Snelheid in m/s volgens de sensor (null = onbekend).
  final speed = ValueNotifier<double?>(null);
  final status = ValueNotifier<HrStatus>(HrStatus.off);
  String? deviceName;
  String? _deviceId;
  bool _wanted = false;
  DateTime? _lastData;

  StreamSubscription<ConnectionStateUpdate>? _conn;
  StreamSubscription<List<int>>? _data;
  Timer? _retry;
  Timer? _stale;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _deviceId = p.getString(_idKey);
      deviceName = p.getString(_nameKey);
    } catch (_) {}
  }

  bool get hasSavedDevice => _deviceId != null;

  /// Zoekt loopsensoren in de buurt.
  Stream<DiscoveredDevice> scan() {
    status.value = HrStatus.scanning;
    return _ble.scanForDevices(withServices: [service], scanMode: ScanMode.lowLatency, requireLocationServicesEnabled: false);
  }

  void stopScan() {
    if (status.value == HrStatus.scanning) status.value = HrStatus.off;
  }

  Future<void> connect(String id, String name) async {
    _deviceId = id;
    deviceName = name.isEmpty ? 'Loopsensor' : name;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_idKey, id);
      await p.setString(_nameKey, deviceName!);
    } catch (_) {}
    _wanted = true;
    await _open();
  }

  /// Verbinden met de onthouden sensor (bij het starten van een run).
  Future<void> autoConnect() async {
    if (_deviceId == null || status.value == HrStatus.connected || status.value == HrStatus.connecting) return;
    if (!await HeartRateService.instance.ensurePermissions()) return;
    _wanted = true;
    await _open();
  }

  /// Een meting binnen (van de eigen sensor of van een hartslagband met dezelfde dienst).
  void onPayload(List<int> data) {
    final s = parseRunningSpeedCadence(data);
    if (s == null) return;
    cadence.value = s.cadence;
    speed.value = s.speed != null && s.speed! > 0 && s.speed! < 10 ? s.speed : null;
    _lastData = DateTime.now();
    // Zonder nieuwe metingen na 5 s: niet blijven doen alsof.
    _stale ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (_lastData == null || DateTime.now().difference(_lastData!) > const Duration(seconds: 5)) {
        cadence.value = null;
        speed.value = null;
      }
    });
  }

  Future<void> _open() async {
    final id = _deviceId;
    if (id == null) return;
    await _close();
    status.value = HrStatus.connecting;
    _conn = _ble
        .connectToDevice(
      id: id,
      servicesWithCharacteristicsToDiscover: {service: [measurement]},
      connectionTimeout: const Duration(seconds: 12),
    )
        .listen((u) {
      switch (u.connectionState) {
        case DeviceConnectionState.connected:
          status.value = HrStatus.connected;
          _data?.cancel();
          _data = _ble
              .subscribeToCharacteristic(QualifiedCharacteristic(characteristicId: measurement, serviceId: service, deviceId: id))
              .listen(onPayload, onError: (Object _) {});
        case DeviceConnectionState.disconnected:
          cadence.value = null;
          speed.value = null;
          status.value = _wanted ? HrStatus.lost : HrStatus.off;
          _scheduleRetry();
        default:
          break;
      }
    }, onError: (Object _) {
      status.value = _wanted ? HrStatus.lost : HrStatus.off;
      _scheduleRetry();
    });
  }

  void _scheduleRetry() {
    _retry?.cancel();
    if (!_wanted) return;
    _retry = Timer(const Duration(seconds: 6), () {
      if (_wanted && status.value != HrStatus.connected) _open();
    });
  }

  Future<void> _close() async {
    _retry?.cancel();
    await _data?.cancel();
    await _conn?.cancel();
    _data = null;
    _conn = null;
  }

  Future<void> disconnect() async {
    _wanted = false;
    await _close();
    cadence.value = null;
    speed.value = null;
    status.value = HrStatus.off;
  }

  Future<void> forget() async {
    await disconnect();
    _deviceId = null;
    deviceName = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_idKey);
      await p.remove(_nameKey);
    } catch (_) {}
  }
}

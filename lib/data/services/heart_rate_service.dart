import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/heart_rate.dart';
import 'stride_sensor_service.dart';

enum HrStatus { off, scanning, connecting, connected, lost }

/// Hartslagband (Polar, Garmin HRM, Wahoo, Coros, ...) via Bluetooth, de standaard hartslag-dienst.
class HeartRateService {
  HeartRateService._();
  static final instance = HeartRateService._();

  static final _service = Uuid.parse('180D');
  static final _measurement = Uuid.parse('2A37');
  static const _idKey = 'hr_device_id';
  static const _nameKey = 'hr_device_name';
  static const _maxKey = 'hr_max';

  final _ble = FlutterReactiveBle();
  final bpm = ValueNotifier<int?>(null);
  final status = ValueNotifier<HrStatus>(HrStatus.off);
  final maxHr = ValueNotifier<int>(190);
  String? deviceName;
  String? _deviceId;
  bool _wanted = false;

  StreamSubscription<ConnectionStateUpdate>? _conn;
  StreamSubscription<List<int>>? _data;
  StreamSubscription<List<int>>? _rsc;
  Timer? _retry;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _deviceId = p.getString(_idKey);
      deviceName = p.getString(_nameKey);
      maxHr.value = p.getInt(_maxKey) ?? 190;
    } catch (_) {}
  }

  bool get hasSavedDevice => _deviceId != null;

  Future<void> setMaxHr(int v) async {
    maxHr.value = v.clamp(140, 220);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_maxKey, maxHr.value);
  }

  /// Toestemming voor Bluetooth (Android 12+) en anders locatie (oudere Android).
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final res = await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
    final scan = res[Permission.bluetoothScan], connect = res[Permission.bluetoothConnect];
    final bt = (scan?.isGranted ?? false) && (connect?.isGranted ?? false);
    final loc = res[Permission.locationWhenInUse]?.isGranted ?? false;
    return bt || loc;
  }

  /// Zoekt banden in de buurt (alleen apparaten met de hartslag-dienst).
  Stream<DiscoveredDevice> scan() {
    status.value = HrStatus.scanning;
    return _ble.scanForDevices(withServices: [_service], scanMode: ScanMode.lowLatency, requireLocationServicesEnabled: false);
  }

  void stopScan() {
    if (status.value == HrStatus.scanning) status.value = HrStatus.off;
  }

  /// Koppelen en onthouden.
  Future<void> connect(String id, String name) async {
    _deviceId = id;
    deviceName = name.isEmpty ? 'Hartslagband' : name;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_idKey, id);
      await p.setString(_nameKey, deviceName!);
    } catch (_) {}
    _wanted = true;
    await _open();
  }

  /// Verbinden met de onthouden band (bijv. bij het starten van een run).
  Future<void> autoConnect() async {
    if (_deviceId == null || status.value == HrStatus.connected || status.value == HrStatus.connecting) return;
    if (!await ensurePermissions()) return;
    _wanted = true;
    await _open();
  }

  Future<void> _open() async {
    final id = _deviceId;
    if (id == null) return;
    await _close();
    status.value = HrStatus.connecting;
    _conn = _ble
        .connectToDevice(
      id: id,
      servicesWithCharacteristicsToDiscover: {_service: [_measurement]},
      connectionTimeout: const Duration(seconds: 12),
    )
        .listen((u) {
      switch (u.connectionState) {
        case DeviceConnectionState.connected:
          status.value = HrStatus.connected;
          _subscribe(id);
        case DeviceConnectionState.disconnected:
          bpm.value = null;
          status.value = _wanted ? HrStatus.lost : HrStatus.off;
          _scheduleRetry();
        default:
          break;
      }
    }, onError: (Object _) {
      bpm.value = null;
      status.value = _wanted ? HrStatus.lost : HrStatus.off;
      _scheduleRetry();
    });
  }

  void _subscribe(String id) {
    _data?.cancel();
    _data = _ble
        .subscribeToCharacteristic(QualifiedCharacteristic(characteristicId: _measurement, serviceId: _service, deviceId: id))
        .listen((d) {
      final v = parseHeartRateMeasurement(d);
      if (v != null && v > 25 && v < 240) bpm.value = v;
    }, onError: (Object _) {});
    // Sommige banden (Wahoo Tickr X, Garmin HRM-Pro) geven ook cadans via de loopsensor-dienst.
    // Heeft de band die niet, dan komt er een fout die we negeren.
    _rsc?.cancel();
    _rsc = _ble
        .subscribeToCharacteristic(QualifiedCharacteristic(
            characteristicId: StrideSensorService.measurement, serviceId: StrideSensorService.service, deviceId: id))
        .listen(StrideSensorService.instance.onPayload, onError: (Object _) {});
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
    await _rsc?.cancel();
    await _conn?.cancel();
    _data = null;
    _rsc = null;
    _conn = null;
  }

  /// Verbinding verbreken (band blijft onthouden).
  Future<void> disconnect() async {
    _wanted = false;
    await _close();
    bpm.value = null;
    status.value = HrStatus.off;
  }

  /// Band vergeten.
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

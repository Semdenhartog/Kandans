import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../core/theme.dart';
import '../../data/services/heart_rate_service.dart';
import '../../domain/heart_rate.dart';
import '../../shared/widgets.dart';

void openHeartRateScreen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HeartRateScreen()));
}

/// Hartslagband koppelen, live testen en je maximale hartslag instellen.
class HeartRateScreen extends StatefulWidget {
  const HeartRateScreen({super.key});

  @override
  State<HeartRateScreen> createState() => _HeartRateScreenState();
}

class _HeartRateScreenState extends State<HeartRateScreen> {
  final _hr = HeartRateService.instance;
  final _found = <String, DiscoveredDevice>{};
  StreamSubscription<DiscoveredDevice>? _scan;
  Timer? _stop;
  String? _error;

  @override
  void dispose() {
    _stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _error = null;
      _found.clear();
    });
    if (!await _hr.ensurePermissions()) {
      setState(() => _error = 'Kadans mag Bluetooth niet gebruiken. Zet "Apparaten in de buurt" aan bij de app-rechten.');
      return;
    }
    _scan = _hr.scan().listen((d) {
      if (mounted) setState(() => _found[d.id] = d);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = 'Zoeken lukt niet. Staat Bluetooth aan?');
      _stopScan();
    });
    _stop = Timer(const Duration(seconds: 15), _stopScan);
    setState(() {});
  }

  void _stopScan() {
    _stop?.cancel();
    _scan?.cancel();
    _scan = null;
    _hr.stopScan();
    if (mounted) setState(() {});
  }

  Future<void> _connect(DiscoveredDevice d) async {
    _stopScan();
    await _hr.connect(d.id, d.name);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scanning = _scan != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Hartslagband')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RwCard(
            child: ValueListenableBuilder<HrStatus>(
              valueListenable: _hr.status,
              builder: (context, st, _) => ValueListenableBuilder<int?>(
                valueListenable: _hr.bpm,
                builder: (context, bpm, _) {
                  final zone = bpm == null ? 0 : heartRateZone(bpm, _hr.maxHr.value);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.favorite, color: bpm == null ? RwColors.subtle : RwColors.danger, size: 36),
                          const SizedBox(width: 12),
                          Text(bpm == null ? '–' : '$bpm',
                              style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 48, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 6),
                          Text('bpm', style: TextStyle(color: RwColors.muted)),
                          const Spacer(),
                          if (zone > 0)
                            Chip(label: Text('Zone $zone · ${heartRateZoneNames[zone]}')),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        switch (st) {
                          HrStatus.connected => 'Verbonden met ${_hr.deviceName ?? 'je band'}',
                          HrStatus.connecting => 'Verbinden met ${_hr.deviceName ?? 'je band'}…',
                          HrStatus.lost => 'Verbinding kwijt, we proberen het opnieuw…',
                          HrStatus.scanning => 'Zoeken naar banden…',
                          HrStatus.off => _hr.hasSavedDevice
                              ? '${_hr.deviceName} is onthouden. Hij verbindt vanzelf als je een run start.'
                              : 'Nog geen band gekoppeld.',
                        },
                        style: TextStyle(color: RwColors.muted),
                      ),
                      if (_hr.hasSavedDevice) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (st != HrStatus.connected && st != HrStatus.connecting)
                              OutlinedButton(onPressed: () => _hr.autoConnect().then((_) => setState(() {})), child: const Text('Nu verbinden')),
                            if (st == HrStatus.connected)
                              OutlinedButton(onPressed: () => _hr.disconnect().then((_) => setState(() {})), child: const Text('Verbreken')),
                            TextButton(
                              onPressed: () => _hr.forget().then((_) => setState(() {})),
                              child: Text('Vergeten', style: TextStyle(color: RwColors.danger)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: scanning ? _stopScan : _startScan,
            icon: Icon(scanning ? Icons.stop : Icons.bluetooth_searching),
            label: Text(scanning ? 'Stoppen met zoeken' : 'Zoek een hartslagband'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: RwColors.danger)),
          ],
          if (scanning || _found.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (_found.isEmpty)
              Padding(
                padding: EdgeInsets.all(12),
                child: Text('Doe je band om (vaak gaat hij pas aan als hij huid voelt) en houd hem dichtbij.',
                    style: TextStyle(color: RwColors.muted)),
              ),
            for (final d in _found.values)
              Card(
                child: ListTile(
                  leading: TileIcon(Icons.monitor_heart_outlined, color: RwColors.accent),
                  title: Text(d.name.isEmpty ? 'Onbekende band' : d.name),
                  subtitle: Text('Signaal ${d.rssi} dBm'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _connect(d),
                ),
              ),
          ],
          const SizedBox(height: 16),
          RwCard(
            title: 'MAXIMALE HARTSLAG',
            child: ValueListenableBuilder<int>(
              valueListenable: _hr.maxHr,
              builder: (context, max, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                          tooltip: 'Lager', onPressed: () => _hr.setMaxHr(max - 1), icon: const Icon(Icons.remove_circle_outline)),
                      Text('$max bpm', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      IconButton(
                          tooltip: 'Hoger', onPressed: () => _hr.setMaxHr(max + 1), icon: const Icon(Icons.add_circle_outline)),
                    ],
                  ),
                  Text(
                    'Hiermee rekent Kadans je hartslagzones uit. Zone 2 (rustig) is ${(max * 0.6).round()}–${(max * 0.7).round()} bpm. '
                    'Weet je het niet precies? Een vuistregel is 220 min je leeftijd.',
                    style: TextStyle(color: RwColors.muted, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Werkt met banden die standaard Bluetooth-hartslag uitzenden, zoals Polar H9/H10, Garmin HRM-Dual, Wahoo TICKR en Coros. '
            'Een horloge kan dit soms ook (zet "hartslag uitzenden" aan op je horloge).',
            style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Noodcontact (alleen op deze telefoon bewaard, gaat nooit naar de server).
class EmergencyContact {
  const EmergencyContact(this.name, this.phone);
  final String name;
  final String phone;

  static const _kName = 'sos_name';
  static const _kPhone = 'sos_phone';

  static Future<EmergencyContact?> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final phone = p.getString(_kPhone) ?? '';
      if (phone.trim().isEmpty) return null;
      return EmergencyContact(p.getString(_kName) ?? '', phone);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String name, String phone) async {
    final p = await SharedPreferences.getInstance();
    if (phone.trim().isEmpty) {
      await p.remove(_kName);
      await p.remove(_kPhone);
    } else {
      await p.setString(_kName, name.trim());
      await p.setString(_kPhone, phone.trim());
    }
  }
}

/// Instelling op "Ik".
class EmergencyContactTile extends StatefulWidget {
  const EmergencyContactTile({super.key});

  @override
  State<EmergencyContactTile> createState() => _EmergencyContactTileState();
}

class _EmergencyContactTileState extends State<EmergencyContactTile> {
  EmergencyContact? _c;

  @override
  void initState() {
    super.initState();
    EmergencyContact.load().then((c) {
      if (mounted) setState(() => _c = c);
    });
  }

  Future<void> _edit() async {
    final name = TextEditingController(text: _c?.name ?? '');
    final phone = TextEditingController(text: _c?.phone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Noodcontact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tijdens een run kun je met de SOS-knop dit contact een sms sturen met je locatie. '
              'Het nummer blijft alleen op deze telefoon.',
              style: TextStyle(color: RwColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Naam'), textCapitalization: TextCapitalization.words),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Telefoonnummer'), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Opslaan')),
        ],
      ),
    );
    if (ok != true) return;
    await EmergencyContact.save(name.text, phone.text);
    final c = await EmergencyContact.load();
    if (mounted) setState(() => _c = c);
  }

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const TileIcon(Icons.sos_outlined, color: RwColors.danger),
        title: const Text('Noodcontact'),
        subtitle: Text(_c == null
            ? 'Stel iemand in die je met één tik je locatie stuurt'
            : '${_c!.name.isEmpty ? _c!.phone : _c!.name} · via de SOS-knop tijdens je run'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _edit,
      );
}

/// SOS tijdens een run: je locatie sturen of 112 bellen.
Future<void> showSosSheet(BuildContext context) async {
  final contact = await EmergencyContact.load();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Hulp nodig?', style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: RwColors.danger, minimumSize: const Size.fromHeight(52)),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: '112')),
              icon: const Icon(Icons.call),
              label: const Text('Bel 112'),
            ),
            const SizedBox(height: 10),
            if (contact != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () async {
                  String where = '';
                  try {
                    final p = await Geolocator.getLastKnownPosition() ??
                        await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 8));
                    where = ' Mijn locatie: https://maps.google.com/?q=${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';
                  } catch (_) {}
                  final body = 'Ik ben aan het hardlopen en heb hulp nodig.$where';
                  final ok = await launchUrl(Uri(scheme: 'sms', path: contact.phone, queryParameters: {'body': body}));
                  if (!ok && ctx.mounted) showMessage(ctx, 'Sms-app kon niet worden geopend.', error: true);
                },
                icon: const Icon(Icons.sms_outlined),
                label: Text('Stuur locatie naar ${contact.name.isEmpty ? contact.phone : contact.name}'),
              )
            else
              const Text(
                'Tip: stel op "Ik" een noodcontact in, dan kun je hier met één tik je locatie sturen.',
                style: TextStyle(color: RwColors.subtle),
              ),
          ],
        ),
      ),
    ),
  );
}

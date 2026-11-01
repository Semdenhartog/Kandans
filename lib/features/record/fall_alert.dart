import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/run_recorder_service.dart';
import '../profile/emergency_contact.dart';

/// Toont "Gaat het?" over het opnamescherm zodra Kadans een val vermoedt.
class FallAlertWatcher extends StatefulWidget {
  const FallAlertWatcher({super.key, required this.child});
  final Widget child;

  @override
  State<FallAlertWatcher> createState() => _FallAlertWatcherState();
}

class _FallAlertWatcherState extends State<FallAlertWatcher> {
  final _svc = RunRecorderService.instance;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _svc.fallCountdown.addListener(_changed);
  }

  @override
  void dispose() {
    _svc.fallCountdown.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final v = _svc.fallCountdown.value;
    if (v != null && !_open && mounted) {
      _open = true;
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) => const _FallDialog(),
      ).whenComplete(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FallDialog extends StatefulWidget {
  const _FallDialog();

  @override
  State<_FallDialog> createState() => _FallDialogState();
}

class _FallDialogState extends State<_FallDialog> {
  final _svc = RunRecorderService.instance;
  EmergencyContact? _contact;

  @override
  void initState() {
    super.initState();
    EmergencyContact.load().then((c) {
      if (mounted) setState(() => _contact = c);
    });
    _svc.fallCountdown.addListener(_closeIfDone);
  }

  @override
  void dispose() {
    _svc.fallCountdown.removeListener(_closeIfDone);
    super.dispose();
  }

  void _closeIfDone() {
    if (_svc.fallCountdown.value == null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ValueListenableBuilder<int?>(
              valueListenable: _svc.fallCountdown,
              builder: (context, left, _) {
                final alarm = left == 0;
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Spacer(),
                  Icon(alarm ? Icons.warning_amber_rounded : Icons.personal_injury_outlined, size: 72, color: alarm ? RwColors.danger : Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    alarm ? tr('Waarschuwing gegeven') : tr('Gaat het?'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontFamily: RwFonts.display, fontSize: 34, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    alarm
                        ? tr('Je reageerde niet. Wie je live volgt, ziet nu een melding. Bel hieronder je noodcontact of 112.')
                        : trf('Het leek alsof je viel. Als je niet reageert, waarschuwt Kadans over {s} seconden.', {'s': left ?? 0}),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.45),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), backgroundColor: RwColors.good, foregroundColor: Colors.black),
                    onPressed: _svc.fallOk,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(tr('Het gaat goed'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 12),
                  if (_contact != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                      onPressed: () => launchUrl(Uri(scheme: 'tel', path: _contact!.phone)),
                      icon: const Icon(Icons.call_outlined),
                      label: Text(trf('Bel {naam}', {'naam': _contact!.name.isEmpty ? _contact!.phone : _contact!.name})),
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: Colors.white, side: BorderSide(color: RwColors.danger)),
                    onPressed: () => showSosSheet(context),
                    icon: const Icon(Icons.sos_outlined),
                    label: Text(tr('Hulp nodig (112 of locatie sturen)')),
                  ),
                ]);
              },
            ),
          ),
        ),
      );
}

/// Schakelaar in de instellingen van het opnemen.
class FallDetectTile extends StatefulWidget {
  const FallDetectTile({super.key});

  @override
  State<FallDetectTile> createState() => _FallDetectTileState();
}

class _FallDetectTileState extends State<FallDetectTile> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _on = p.getBool(RunRecorderService.fallPrefKey) ?? true);
    }).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Valdetectie')),
        subtitle: Text(tr('Na een harde val en stilliggen vraagt Kadans "Gaat het?". Reageer je niet binnen een minuut, dan zien je live-kijkers een melding en gaat er een alarm af.')),
        value: _on ?? true,
        onChanged: _on == null
            ? null
            : (v) {
                setState(() => _on = v);
                SharedPreferences.getInstance().then((p) => p.setBool(RunRecorderService.fallPrefKey, v)).ignore();
              },
      );
}

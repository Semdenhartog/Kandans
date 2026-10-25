import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/live_share_service.dart';
import '../../shared/widgets.dart';

void openLiveShare(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LiveShareScreen()));
}

Future<void> _shareLink(String url, String name) =>
    SharePlus.instance.share(ShareParams(
      text: '${name.isEmpty ? 'Ik' : name} ga hardlopen. Kijk hier live mee waar ik ben: $url',
      subject: 'Live meelopen met Kadans',
    ));

/// Kaartje op Vandaag: live delen starten of de status zien.
class LiveShareEntryCard extends StatefulWidget {
  const LiveShareEntryCard({super.key});

  @override
  State<LiveShareEntryCard> createState() => _LiveShareEntryCardState();
}

class _LiveShareEntryCardState extends State<LiveShareEntryCard> {
  @override
  void initState() {
    super.initState();
    LiveShareService.instance.restore();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiveShareState>(
      valueListenable: LiveShareService.instance.state,
      builder: (context, s, _) {
        final on = s.isOn || s.status == LiveStatus.paused;
        return RwCard(
          title: on ? 'LIVE DELEN STAAT AAN' : 'VEILIG ONDERWEG',
          onTap: () => openLiveShare(context),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (on ? RwColors.good : RwColors.accent).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(on ? Icons.share_location : Icons.location_on_outlined,
                    color: on ? RwColors.good : RwColors.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  on
                      ? (s.status == LiveStatus.paused
                          ? 'Je gedeelde run staat nog open. Tik om verder te delen of te stoppen.'
                          : 'Je locatie wordt gedeeld${s.lastSentAt == null ? '' : ', laatste update ${Fmt.time(s.lastSentAt!)}'}.')
                      : 'Ga je lopen? Deel je live locatie met iemand thuis. Gratis, en stopt vanzelf.',
                  style: const TextStyle(height: 1.4),
                ),
              ),
              Icon(Icons.chevron_right, color: RwColors.subtle),
            ],
          ),
        );
      },
    );
  }
}

/// Live locatie delen: starten, link delen, stoppen.
class LiveShareScreen extends ConsumerStatefulWidget {
  const LiveShareScreen({super.key});

  @override
  ConsumerState<LiveShareScreen> createState() => _LiveShareScreenState();
}

class _LiveShareScreenState extends ConsumerState<LiveShareScreen> {
  final _name = TextEditingController();
  int _hours = 2;
  bool _busy = false;
  Timer? _tick;

  final _service = LiveShareService.instance;

  @override
  void initState() {
    super.initState();
    _service.restore();
    final p = ref.read(profileProvider).value;
    final n = p?.displayName ?? '';
    _name.text = n == 'loper' ? '' : n;
    // Elke 20 s opnieuw tekenen voor "x min geleden".
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final url = await _service.start(name: _name.text, duration: Duration(hours: _hours));
      if (!mounted) return;
      await _shareLink(url, _name.text.trim());
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resume() async {
    setState(() => _busy = true);
    try {
      await _service.resume();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    await _service.stop();
    if (mounted) {
      setState(() => _busy = false);
      showMessage(context, 'Live delen gestopt. Je locatie is gewist.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live locatie delen')),
      body: ValueListenableBuilder<LiveShareState>(
        valueListenable: _service.state,
        builder: (context, s, _) {
          final on = s.isOn || s.status == LiveStatus.paused || s.status == LiveStatus.stopping;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: on ? _active(s) : _setup(),
          );
        },
      ),
    );
  }

  List<Widget> _setup() => [
        Text(
          'Stuur iemand een link. Die ziet op een kaart waar je bent tijdens je run, zonder app of account.',
          style: TextStyle(color: RwColors.muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        RwCard(
          title: 'JE NAAM IN DE LINK',
          child: TextField(
            controller: _name,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Bijv. Sem', counterText: ''),
          ),
        ),
        const SizedBox(height: 12),
        RwCard(
          title: 'STOPT VANZELF NA',
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1 uur')),
              ButtonSegment(value: 2, label: Text('2 uur')),
              ButtonSegment(value: 3, label: Text('3 uur')),
              ButtonSegment(value: 5, label: Text('5 uur')),
            ],
            selected: {_hours},
            onSelectionChanged: (v) => setState(() => _hours = v.first),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _start,
          icon: _busy
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: RwColors.accentDark))
              : const Icon(Icons.share_location),
          label: const Text('Start en deel de link'),
        ),
        const SizedBox(height: 16),
        const _Privacy(),
      ];

  List<Widget> _active(LiveShareState s) {
    final url = s.url ?? '';
    final sent = s.lastSentAt;
    final ago = sent == null ? null : DateTime.now().difference(sent);
    final expires = s.expiresAt?.toLocal();
    final paused = s.status == LiveStatus.paused;
    return [
      RwCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(paused ? Icons.pause_circle_outline : Icons.circle,
                    size: paused ? 22 : 14, color: paused ? RwColors.warning : RwColors.good),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    paused
                        ? 'Gepauzeerd: je locatie wordt niet bijgewerkt'
                        : s.status == LiveStatus.starting
                            ? 'Wacht op GPS…'
                            : 'Live: je locatie wordt gedeeld',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              [
                if (ago != null) 'Laatste update ${ago.inSeconds < 60 ? '${ago.inSeconds} s' : '${ago.inMinutes} min'} geleden',
                if (s.updates > 0) '${s.updates} updates verstuurd',
                if (expires != null) 'stopt vanzelf om ${Fmt.time(expires)}',
              ].join(' · '),
              style: TextStyle(color: RwColors.muted, height: 1.4),
            ),
            if (s.error != null) ...[
              const SizedBox(height: 8),
              Text(s.error!, style: TextStyle(color: RwColors.warning)),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      RwCard(
        title: 'JE LINK',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(url, style: TextStyle(color: RwColors.accent)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (mounted) showMessage(context, 'Link gekopieerd.');
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Kopiëren'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _shareLink(url, _name.text.trim()),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Delen'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (paused)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FilledButton.icon(
            onPressed: _busy ? null : _resume,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Verder delen'),
          ),
        ),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: RwColors.danger, foregroundColor: RwColors.background),
        onPressed: _busy || s.status == LiveStatus.stopping ? null : _stop,
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('Stop met delen'),
      ),
      const SizedBox(height: 16),
      const _Privacy(),
    ];
  }
}

class _Privacy extends StatelessWidget {
  const _Privacy();

  @override
  Widget build(BuildContext context) => Text(
        'Privacy: alleen wie de link heeft, kan meekijken. Bij stoppen wissen we je route en locatie direct van de server. '
        'Zolang je deelt, staat er een melding op je telefoon, ook als Kadans op de achtergrond draait.',
        style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.5),
      );
}

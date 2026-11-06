import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../data/services/kadans_voice.dart';
import 'widgets.dart';

/// Keuzelijst van de Kadans-stemmen (2 mannen, 2 vrouwen), elk met een knop die een kort voorbeeld laat horen.
/// Gebruikt in de rondleiding en in de stemkeuze bij Opnemen.
class KadansVoiceChooser extends StatefulWidget {
  const KadansVoiceChooser({super.key, this.onPicked});

  /// Na het kiezen (bijv. om in de rondleiding door te gaan).
  final ValueChanged<KadansVoiceOption>? onPicked;

  @override
  State<KadansVoiceChooser> createState() => _KadansVoiceChooserState();
}

class _KadansVoiceChooserState extends State<KadansVoiceChooser> {
  String? _chosen;
  String? _playing;

  @override
  void initState() {
    super.initState();
    KadansVoice.instance.choice().then((k) {
      if (mounted) setState(() => _chosen = k);
    });
  }

  Future<void> _pick(KadansVoiceOption v) async {
    HapticFeedback.selectionClick();
    setState(() => _chosen = v.key);
    await KadansVoice.instance.setChoice(v.key);
    await KadansVoice.instance.setEnabled(true);
    widget.onPicked?.call(v);
  }

  Future<void> _preview(KadansVoiceOption v) async {
    if (_playing != null) return;
    setState(() => _playing = v.key);
    final err = await KadansVoice.instance.preview(v);
    if (!mounted) return;
    setState(() => _playing = null);
    if (err != null) showMessage(context, err, error: true);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in kadansVoices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _VoiceRow(
                option: v,
                selected: _chosen == v.key,
                playing: _playing == v.key,
                onTap: () => _pick(v),
                onPreview: () => _preview(v),
              ),
            ),
        ],
      );
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.option,
    required this.selected,
    required this.playing,
    required this.onTap,
    required this.onPreview,
  });
  final KadansVoiceOption option;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final who = option.female ? tr('Vrouw') : tr('Man');
    return Material(
      color: selected ? RwColors.accent.withValues(alpha: 0.16) : RwColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RwRadius.m),
        side: BorderSide(color: selected ? RwColors.accent : RwColors.bar, width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(RwRadius.m),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: RwColors.accent.withValues(alpha: 0.18),
              child: Text(option.name[0],
                  style: TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, color: RwColors.accent)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(option.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text('$who · ${tr(option.style)}', style: TextStyle(color: RwColors.muted, fontSize: 13)),
              ]),
            ),
            if (selected) Icon(Icons.check_circle, size: 20, color: RwColors.accent),
            IconButton(
              tooltip: trf('Laat {naam} horen', {'naam': option.name}),
              onPressed: onPreview,
              icon: playing
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.play_circle_fill, size: 30, color: RwColors.accent),
            ),
          ]),
        ),
      ),
    );
  }
}

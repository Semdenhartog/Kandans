import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'runner_avatar.dart';

/// Kies je profielplaatje (icoon + kleur) en je omslag in Samen.
Future<void> openAvatarPicker(BuildContext context, String nickname) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Picker(nickname: nickname),
    );

String coverLabel(String c) => switch (c) {
      'winter' => tr('Winter'),
      'lente' => tr('Lente'),
      'zomer' => tr('Zomer'),
      'hei' => tr('Paarse hei'),
      'herfst' => tr('Herfst'),
      'mist' => tr('Mist'),
      _ => tr('Seizoen van nu'),
    };

class _Picker extends StatefulWidget {
  const _Picker({required this.nickname});
  final String nickname;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  late AvatarStyle _s = AvatarCache.instance.peek(widget.nickname) ?? const AvatarStyle();
  bool _saving = false;

  void _set({String? icon, int? color, String? cover, bool clearIcon = false}) => setState(() => _s = AvatarStyle(
        icon: clearIcon ? null : (icon ?? _s.icon),
        color: color ?? _s.color,
        cover: cover ?? _s.cover,
      ));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('social_set_avatar', params: {
        'p_icon': _s.icon,
        'p_color': _s.color,
        'p_cover': _s.cover ?? 'auto',
      });
      AvatarCache.instance.setMine(widget.nickname, _s);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, tr('Opslaan lukte niet. Probeer het later nog eens.'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(alignment: Alignment.bottomLeft, children: [
                ProfileCover(nickname: widget.nickname, height: 110, style: _s),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: RunnerAvatar(widget.nickname, size: 64, style: _s),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Text(tr('Plaatje'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _Choice(
                selected: _s.icon == null,
                onTap: () => _set(clearIcon: true),
                child: Text(widget.nickname.isEmpty ? '?' : widget.nickname.characters.first.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              for (final e in avatarIcons.entries)
                _Choice(selected: _s.icon == e.key, onTap: () => _set(icon: e.key), child: Icon(e.value)),
            ]),
            const SizedBox(height: 16),
            Text(tr('Kleur'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (var i = 0; i < avatarColors.length; i++)
                Semantics(
                  button: true,
                  selected: _s.color == i,
                  label: trf('Kleur {n}', {'n': i + 1}),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _set(color: i),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: avatarColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(color: _s.color == i ? RwColors.text : Colors.transparent, width: 3),
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            Text(tr('Omslag'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in coverChoices)
                ChoiceChip(label: Text(coverLabel(c)), selected: (_s.cover ?? 'auto') == c, onSelected: (_) => _set(cover: c)),
            ]),
            const SizedBox(height: 20),
            FilledButton(onPressed: _saving ? null : _save, child: Text(tr('Opslaan'))),
          ]),
        ),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.selected, required this.onTap, required this.child});
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: selected ? RwColors.accent.withValues(alpha: 0.18) : RwColors.surfaceHigh,
              border: Border.all(color: selected ? RwColors.accent : RwColors.border, width: selected ? 2 : 1),
            ),
            child: IconTheme(data: IconThemeData(color: selected ? RwColors.accent : RwColors.muted), child: child),
          ),
        ),
      );
}

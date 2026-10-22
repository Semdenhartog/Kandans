import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

/// Korte uitleg die één keer bovenaan een tabblad staat. Wegtikken = nooit meer (tot je de tips
/// opnieuw aanzet in Ik → Hulp).
class FirstTip extends StatefulWidget {
  const FirstTip({
    super.key,
    required this.id,
    required this.icon,
    required this.text,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 8),
  });
  final String id;
  final EdgeInsetsGeometry padding;
  final IconData icon;
  final String text;

  @override
  State<FirstTip> createState() => _FirstTipState();
}

const _prefix = 'tip_seen_';

/// Alle tips opnieuw laten zien.
Future<void> resetFirstTips() async {
  try {
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await p.remove(k);
    }
    firstTipsReset.value++;
  } catch (_) {}
}

/// Telt op als de tips opnieuw aangezet worden, zodat open schermen ze meteen weer tonen.
final firstTipsReset = ValueNotifier<int>(0);

class _FirstTipState extends State<FirstTip> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    firstTipsReset.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    firstTipsReset.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final seen = p.getBool('$_prefix${widget.id}') ?? false;
      if (mounted) setState(() => _show = !seen);
    } catch (_) {}
  }

  Future<void> _dismiss() async {
    setState(() => _show = false);
    try {
      await (await SharedPreferences.getInstance()).setBool('$_prefix${widget.id}', true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: !_show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: widget.padding,
              child: Material(
                color: RwColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(widget.icon, color: RwColors.accent, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(widget.text, style: const TextStyle(height: 1.4))),
                    IconButton(
                      tooltip: 'Tip wegtikken',
                      visualDensity: VisualDensity.compact,
                      onPressed: _dismiss,
                      icon: const Icon(Icons.close, size: 18, color: RwColors.muted),
                    ),
                  ]),
                ),
              ),
            ),
    );
  }
}

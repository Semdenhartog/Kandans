import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../domain/route_anim.dart';

/// Knoppen onder het voorbeeld van de routevideo: stijl, foto, tekst terugzetten, maken en delen.
class RouteAnimControls extends StatelessWidget {
  const RouteAnimControls({
    super.key,
    required this.styles,
    required this.style,
    required this.styleName,
    required this.busy,
    required this.progress,
    required this.hasData,
    required this.hasPhoto,
    required this.layoutChanged,
    required this.hideHome,
    required this.hasVideo,
    required this.error,
    required this.onStyle,
    required this.onPhoto,
    required this.onTitle,
    required this.onClearPhoto,
    required this.onResetLayout,
    required this.onHideHome,
    required this.onMake,
    required this.onStop,
    required this.onShare,
    required this.onInstagram,
  });

  final List<RouteAnimStyle> styles;
  final RouteAnimStyle style;
  final String Function(RouteAnimStyle) styleName;
  final bool busy, hasData, hasPhoto, layoutChanged, hideHome, hasVideo;
  final double? progress;
  final String? error;
  final ValueChanged<RouteAnimStyle> onStyle;
  final VoidCallback onPhoto, onTitle, onClearPhoto, onResetLayout, onMake, onStop, onShare, onInstagram;
  final ValueChanged<bool> onHideHome;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(hasPhoto ? tr('Sleep de tekst, of de foto om hem te verschuiven. Knijp om in te zoomen') : tr('Sleep de tekst of het logo om ze te verplaatsen'), style: TextStyle(fontSize: 12, color: RwColors.muted)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<RouteAnimStyle>(
                showSelectedIcon: false,
                segments: [for (final s in styles) ButtonSegment(value: s, label: Text(styleName(s)))],
                selected: {style},
                onSelectionChanged: busy ? null : (v) => onStyle(v.first),
              ),
              Row(children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: busy ? null : onPhoto,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(hasPhoto ? tr('Andere foto') : tr('Foto erachter')),
                  ),
                ),
                IconButton(onPressed: busy ? null : onTitle, tooltip: tr('Titel boven de video'), icon: const Icon(Icons.edit_outlined)),
                if (hasPhoto) Expanded(child: TextButton(onPressed: busy ? null : onClearPhoto, child: Text(tr('Zonder foto')))),
                if (layoutChanged) Expanded(child: TextButton(onPressed: busy ? null : onResetLayout, child: Text(tr('Teksten terugzetten')))),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: hideHome,
                onChanged: busy ? null : onHideHome,
                title: Text(tr('Verberg waar je woont')),
                subtitle: Text(tr('Laat de eerste en laatste 300 m van je route weg')),
              ),
              if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: TextStyle(color: RwColors.danger))),
              if (busy) ...[
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                TextButton(onPressed: onStop, child: Text(tr('Stoppen'))),
              ] else if (!hasVideo)
                FilledButton.icon(onPressed: hasData ? onMake : null, icon: const Icon(Icons.movie_creation_outlined), label: Text(tr('Maak video')))
              else ...[
                FilledButton.icon(onPressed: onShare, icon: const Icon(Icons.ios_share), label: Text(tr('Deel video'))),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: onInstagram, child: Text(tr('Naar Instagram')))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton(onPressed: onMake, child: Text(tr('Opnieuw maken')))),
                ]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

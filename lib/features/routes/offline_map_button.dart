import 'package:flutter/material.dart';

import '../../core/error_reporter.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/offline_maps.dart';
import '../../domain/geo.dart';
import '../../domain/map_tiles.dart';
import '../../shared/widgets.dart';

/// "Kaart offline bewaren" bij een route: de kaart langs de route komt op de telefoon te staan.
class OfflineMapButton extends StatefulWidget {
  const OfflineMapButton({super.key, required this.routeId, required this.name, required this.track});
  final String routeId;
  final String name;
  final List<LatLng> track;

  @override
  State<OfflineMapButton> createState() => _OfflineMapButtonState();
}

class _OfflineMapButtonState extends State<OfflineMapButton> {
  OfflinePack? _pack;
  TilePlan? _plan;
  bool _loaded = false;
  OfflineCancel? _cancel;
  double _progress = 0;

  bool get _busy => _cancel != null;

  @override
  void initState() {
    super.initState();
    if (inNetherlands(widget.track.first)) _plan = tilePlanForTrack(widget.track);
    OfflineMaps.instance.pack(widget.routeId).then((p) {
      if (mounted) setState(() {
            _pack = p;
            _loaded = true;
          });
    }).ignore();
  }

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).clamp(0.1, 9999).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';

  Future<void> _start() async {
    final plan = _plan;
    if (plan == null) return;
    final cancel = OfflineCancel();
    setState(() {
      _cancel = cancel;
      _progress = 0;
    });
    try {
      final p = await OfflineMaps.instance.download(
        id: widget.routeId,
        name: widget.name,
        track: widget.track,
        plan: plan,
        cancel: cancel,
        onProgress: (d, t) {
          if (mounted && t > 0) setState(() => _progress = d / t);
        },
      );
      if (!mounted) return;
      setState(() => _pack = p);
      if (p != null) showMessage(context, trf('Kaart bewaard ({mb}). Werkt nu ook zonder internet.', {'mb': _mb(p.bytes)}));
    } catch (kErr, kSt) {
      ErrorReporter.report(kErr, kSt, context: 'offline_map_button.dart');
      if (mounted) showMessage(context, tr('Bewaren van de kaart is niet gelukt. Controleer je internet en probeer het opnieuw.'));
    } finally {
      if (mounted) setState(() => _cancel = null);
    }
  }

  Future<void> _remove() async {
    final ok = await confirmDialog(
      context,
      title: tr('Offline kaart verwijderen?'),
      message: tr('De route zelf blijft staan. Alleen de bewaarde kaart gaat weg.'),
      confirmLabel: tr('Verwijderen'),
    );
    if (!ok) return;
    await OfflineMaps.instance.remove(widget.routeId);
    if (mounted) setState(() => _pack = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (_busy) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, value: _progress == 0 ? null : _progress)),
          const SizedBox(width: 10),
          Text(trf('Kaart bewaren… {p}%', {'p': '${(_progress * 100).round()}'}), style: TextStyle(color: RwColors.muted)),
          const SizedBox(width: 6),
          TextButton(onPressed: () => _cancel?.cancelled = true, child: Text(tr('Stoppen'))),
        ]),
      );
    }
    final pack = _pack;
    if (pack != null) {
      return TextButton.icon(
        onPressed: _remove,
        icon: const Icon(Icons.download_done),
        label: Text(trf('Offline bewaard ({mb})', {'mb': _mb(pack.bytes)})),
      );
    }
    final plan = _plan;
    if (plan == null) {
      // Buiten Nederland (PDOK) of een heel lange route: geen knop in plaats van een knop die niets doet.
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      onPressed: _start,
      icon: const Icon(Icons.download_for_offline_outlined),
      label: Text(trf('Kaart offline bewaren (± {mb})', {'mb': _mb(estimateTileBytes(plan.tiles.length))})),
    );
  }
}

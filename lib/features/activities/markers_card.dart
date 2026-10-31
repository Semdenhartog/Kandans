import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/disk_image_cache.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/run_markers.dart';
import '../../shared/widgets.dart';
import '../routes/route_map.dart';
import 'photo_wall_screen.dart' show PhotoPin;

/// Pictogram per soort markering.
IconData markerIcon(MarkerKind k) => switch (k) {
      MarkerKind.view => Icons.landscape_outlined,
      MarkerKind.water => Icons.water_drop_outlined,
      MarkerKind.toilet => Icons.wc_outlined,
      MarkerKind.badPath => Icons.warning_amber_outlined,
      MarkerKind.danger => Icons.report_outlined,
      MarkerKind.dog => Icons.pets_outlined,
      MarkerKind.note => Icons.push_pin_outlined,
    };

/// Speld op de kaart voor een markering.
class MarkerPin extends StatelessWidget {
  const MarkerPin(this.kind, {super.key});
  final MarkerKind kind;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: RwColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: RwColors.accent, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6)],
        ),
        alignment: Alignment.center,
        child: Icon(markerIcon(kind), size: 15, color: RwColors.accent),
      );
}

/// Markeringen die je tijdens deze run zette: op de kaart en als lijst, met foto.
class MarkersCard extends ConsumerWidget {
  const MarkersCard({super.key, required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final json = ref.watch(activityStreamsProvider(activity.id!)).value;
    final markers = markersOf(json);
    if (markers.isEmpty) return const SizedBox.shrink();
    final photos = [for (final m in markers) if (m.photo != null) m.photo!];
    final urls = ref.watch(activityPhotoUrlsProvider(photos.join(','))).value ?? const <String, String>{};
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RwCard(
        title: photos.isEmpty ? tr('MARKERINGEN') : tr('MARKERINGEN EN FOTO\'S'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (activity.trackPolyline != null && activity.trackPolyline!.isNotEmpty) ...[
            SizedBox(
              height: 180,
              child: RouteMap(
                polyline: activity.trackPolyline!,
                compact: true,
                interactive: true,
                showLayerToggle: false,
                extraMarkers: [
                  for (final m in markers)
                    (point: m.point, child: m.photo != null && urls[m.photo] != null ? PhotoPin(url: urls[m.photo]!, path: m.photo!) : MarkerPin(m.kind)),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          for (final m in markers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(markerIcon(m.kind), color: RwColors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(m.title), style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${Fmt.km(m.meters, decimals: 1)} · ${Fmt.duration(m.seconds)}',
                        style: TextStyle(color: RwColors.subtle, fontSize: 12)),
                  ]),
                ),
                if (m.photo != null && urls[m.photo] != null)
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => Scaffold(
                        backgroundColor: Colors.black,
                        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(tr(m.title))),
                        body: InteractiveViewer(
                          maxScale: 4,
                          child: Center(child: Image(image: CachedNetImage(urls[m.photo]!, cacheKey: 'run-photo:${m.photo}'))),
                        ),
                      ),
                    )),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: Image(
                          image: CachedNetImage(urls[m.photo]!, cacheKey: 'run-photo:${m.photo}'),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(color: RwColors.surfaceHigh),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}

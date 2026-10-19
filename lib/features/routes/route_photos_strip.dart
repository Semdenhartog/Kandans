import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/disk_image_cache.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/services/route_photos_service.dart';
import '../../domain/route_photos.dart';
import '../../shared/widgets.dart';
import 'route_shape.dart';

String _km(double m) => 'km ${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')}';

/// Foto met nette laad- en foutweergave.
class NetPhoto extends StatelessWidget {
  const NetPhoto(this.url, {super.key, this.fit = BoxFit.cover, this.cacheKey});
  final String url;
  final BoxFit fit;

  /// Vaste sleutel voor de schijfcache (links van Mapillary veranderen steeds).
  final String? cacheKey;

  @override
  Widget build(BuildContext context) => Image(
        image: CachedNetImage(url, cacheKey: cacheKey),
        fit: fit,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) =>
            sync || frame != null ? child : Container(color: RwColors.surfaceHigh),
        errorBuilder: (context, _, _) => Container(
          color: RwColors.surfaceHigh,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported_outlined, color: RwColors.subtle),
        ),
      );
}

/// "ONDERWEG": straatfoto's en bezienswaardigheden in de volgorde waarin je ze tegenkomt.
class RoutePhotosCard extends ConsumerWidget {
  const RoutePhotosCard({
    super.key,
    required this.polyline,
    required this.length,
    this.reversed = false,
    this.onHighlight,
  });

  final String polyline;
  final double length;
  final bool reversed;

  /// Markeert de plek van de foto op de kaart (0..1), of null om los te laten.
  final ValueChanged<double?>? onHighlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(routePhotosProvider(polyline));
    return RwCard(
      title: 'ONDERWEG',
      child: async.when(
        loading: () => SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, _) => Container(
              width: 200,
              decoration: BoxDecoration(color: RwColors.surfaceHigh, borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        error: (e, _) => Row(
          children: [
            const Expanded(child: Text('Foto\'s laden is niet gelukt.', style: TextStyle(color: RwColors.muted))),
            TextButton(onPressed: () => ref.invalidate(routePhotosProvider(polyline)), child: const Text('Opnieuw')),
          ],
        ),
        data: (rp) {
          final photos = [
            for (final p in rp.photos)
              reversed
                  ? RoutePhoto(
                      source: p.source,
                      url: p.url,
                      thumb: p.thumb,
                      point: p.point,
                      meters: (length - p.meters).clamp(0, length).toDouble(),
                      title: p.title,
                      description: p.description,
                      creator: p.creator,
                      capturedAt: p.capturedAt,
                      link: p.link,
                    )
                  : p,
          ]..sort((a, b) => a.meters.compareTo(b.meters));
          if (photos.isEmpty) {
            return Text(
              !rp.streetConfigured
                  ? 'Hier komen straatfoto\'s van je route zodra Mapillary is ingesteld. Bezienswaardigheden langs deze route zijn er niet gevonden.'
                  : rp.streetFailed
                      ? 'Straatfoto\'s konden niet worden geladen. Trek omlaag om het later opnieuw te proberen.'
                      : 'Langs deze route zijn nog geen foto\'s gevonden.',
              style: const TextStyle(color: RwColors.muted, height: 1.4),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final p = photos[i];
                    return Semantics(
                      button: true,
                      label: '${p.title ?? 'Straatfoto'} bij ${_km(p.meters)}. Tik om groot te bekijken.',
                      child: GestureDetector(
                        onTap: () {
                          onHighlight?.call(length <= 0 ? null : p.meters / length);
                          Navigator.of(context).push(MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (_) => PhotoViewer(photos: photos, initial: i, length: length, onHighlight: onHighlight),
                          ));
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: p.source == PhotoSource.landmark ? 170 : 210,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ExcludeSemantics(child: NetPhoto(p.thumb, cacheKey: '${p.link ?? p.thumb}#thumb')),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Colors.transparent, Colors.transparent, Color(0xCC000000)],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 8,
                                  top: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: RwColors.background.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(999)),
                                    child: Text(_km(p.meters), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                  ),
                                ),
                                Positioned(
                                  left: 10,
                                  right: 10,
                                  bottom: 8,
                                  child: Row(
                                    children: [
                                      Icon(p.source == PhotoSource.landmark ? Icons.place : Icons.streetview,
                                          size: 14, color: p.source == PhotoSource.landmark ? RwColors.accent : Colors.white70),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          p.title ?? 'Straatbeeld',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  if (rp.hasStreet) 'Straatfoto\'s © Mapillary-bijdragers (CC BY-SA 4.0)',
                  if (photos.any((p) => p.source == PhotoSource.landmark)) 'bezienswaardigheden via Wikipedia',
                  if (!rp.streetConfigured) 'straatfoto\'s volgen zodra Mapillary is ingesteld',
                ].join(' · '),
                style: const TextStyle(color: RwColors.subtle, fontSize: 11),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Foto's groot bekijken, vegen voor de volgende, met bron en licentie.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.photos, required this.initial, required this.length, this.onHighlight});
  final List<RoutePhoto> photos;
  final int initial;
  final double length;
  final ValueChanged<double?>? onHighlight;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photos[_i];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${_km(p.meters)} · ${_i + 1} van ${widget.photos.length}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.photos.length,
              onPageChanged: (i) {
                setState(() => _i = i);
                final m = widget.photos[i].meters;
                widget.onHighlight?.call(widget.length <= 0 ? null : m / widget.length);
              },
              itemBuilder: (context, i) => InteractiveViewer(
                maxScale: 4,
                child: Center(
                    child: NetPhoto(widget.photos[i].url,
                        fit: BoxFit.contain, cacheKey: '${widget.photos[i].link ?? widget.photos[i].url}#full')),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(p.title ?? 'Straatbeeld bij ${_km(p.meters)}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  if (p.description != null && p.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(p.description!, style: const TextStyle(color: RwColors.muted)),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    [p.credit, if (p.capturedAt != null) 'opgenomen ${Fmt.date(p.capturedAt!)}'].join(' · '),
                    style: const TextStyle(color: RwColors.subtle, fontSize: 12),
                  ),
                  if (p.link != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => launchUrl(Uri.parse(p.link!), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(p.source == PhotoSource.landmark ? 'Lees meer op Wikipedia' : 'Bekijk op Mapillary'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kleine omslag voor de routelijst: een straatfoto met de vorm van de route erop.
class RouteThumb extends ConsumerWidget {
  const RouteThumb({super.key, required this.polyline, this.size = 76});
  final String polyline;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = ref.watch(routeCoverProvider(polyline)).value;
    return SizedBox(
      width: size,
      height: size,
      child: cover == null
          ? RouteShape(polyline: polyline, strokeWidth: 2)
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(child: NetPhoto(cover.thumb, cacheKey: '${cover.link ?? cover.thumb}#thumb')),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    width: size * 0.42,
                    height: size * 0.42,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: RwColors.background.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
                      child: RouteShape(polyline: polyline, strokeWidth: 1.5),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/disk_image_cache.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets.dart';

void openPhotoWall(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PhotoWallScreen()));

/// Fotomuur: al je runfoto's per maand. Tik op een foto om de run te openen.
class PhotoWallScreen extends ConsumerWidget {
  const PhotoWallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final items = [
      for (final a in runs)
        if (a.id != null)
          for (final p in a.photos) (path: p, run: a),
    ]..sort((x, y) => y.run.startedAt.compareTo(x.run.startedAt));
    final urls = ref.watch(activityPhotoUrlsProvider(items.map((e) => e.path).join(','))).value ?? const <String, String>{};
    final fmt = DateFormat('MMMM y', LanguageController.instance.lang.intlLocale);

    final months = <String, List<({String path, Activity run})>>{};
    for (final e in items) {
      (months[fmt.format(e.run.startedAt.toLocal())] ??= []).add(e);
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('Fotomuur'))),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.photo_library_outlined,
              title: tr('Nog geen foto\'s'),
              message: tr('Voeg een foto toe bij een run, of maak er een met "Markeren" tijdens het lopen. Ze komen hier per maand te staan.'),
            )
          : CustomScrollView(slivers: [
              for (final m in months.entries) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text('${m.key.toUpperCase()} · ${m.value.length}', style: RwText.overline),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    children: [
                      for (final (i, e) in m.value.indexed)
                        _Tile(
                          url: urls[e.path],
                          path: e.path,
                          big: i == 0,
                          onTap: () => context.go('/runs/${e.run.id}'),
                        ),
                    ],
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.url, required this.path, required this.onTap, this.big = false});
  final String? url;
  final String path;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tr('Foto, tik om de run te openen'),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: url == null
                ? Container(color: RwColors.surfaceHigh)
                : Image(
                    image: CachedNetImage(url!, cacheKey: 'run-photo:$path'),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(color: RwColors.surfaceHigh),
                  ),
          ),
        ),
      );
}

/// Foto als speld op de kaart (voor markeringen met een foto).
class PhotoPin extends StatelessWidget {
  const PhotoPin({super.key, required this.url, required this.path});
  final String url;
  final String path;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image(
            image: CachedNetImage(url, cacheKey: 'run-photo:$path'),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(color: RwColors.surfaceHigh),
          ),
        ),
      );
}

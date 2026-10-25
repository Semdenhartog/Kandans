import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/disk_image_cache.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets.dart';

/// Foto's bij een run: toevoegen met camera of uit je galerij, groot bekijken en verwijderen.
class PhotosCard extends ConsumerStatefulWidget {
  const PhotosCard({super.key, required this.activity});
  final Activity activity;

  static const maxPhotos = 6;

  @override
  ConsumerState<PhotosCard> createState() => _PhotosCardState();
}

class _PhotosCardState extends ConsumerState<PhotosCard> {
  bool _busy = false;

  Future<void> _add() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Foto maken'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Kies uit je galerij'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(repositoryProvider).addActivityPhoto(widget.activity.id!, bytes);
      ref.invalidate(activitiesProvider);
      if (mounted) showMessage(context, 'Foto toegevoegd.');
    } catch (e) {
      if (mounted) showMessage(context, 'Foto toevoegen is niet gelukt: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String path) async {
    final ok = await confirmDialog(context, title: 'Foto verwijderen?', message: 'De foto wordt definitief verwijderd.');
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).removeActivityPhoto(widget.activity.id!, path);
      ref.invalidate(activitiesProvider);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paths = widget.activity.photos;
    final urls = ref.watch(activityPhotoUrlsProvider(paths.join(','))).value ?? const <String, String>{};
    final canAdd = paths.length < PhotosCard.maxPhotos;
    return RwCard(
      title: 'FOTO\'S',
      child: SizedBox(
        height: 110,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final (i, p) in paths.indexed)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: urls[p] == null
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (_) => _Viewer(urls: [for (final x in paths) urls[x] ?? ''], keys: paths, initial: i),
                          )),
                  onLongPress: () => _remove(p),
                  child: Semantics(
                    label: 'Foto ${i + 1}. Lang drukken om te verwijderen.',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 110,
                        child: urls[p] == null
                            ? Container(color: RwColors.surfaceHigh)
                            : Image(
                                image: CachedNetImage(urls[p]!, cacheKey: 'run-photo:$p'),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(color: RwColors.surfaceHigh),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            if (canAdd)
              Semantics(
                button: true,
                label: 'Foto toevoegen',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _busy ? null : _add,
                  child: Container(
                    width: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: RwColors.border, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_outlined, color: RwColors.accent),
                              SizedBox(height: 6),
                              Text('Toevoegen', style: TextStyle(color: RwColors.muted, fontSize: 12)),
                            ],
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Viewer extends StatelessWidget {
  const _Viewer({required this.urls, required this.keys, required this.initial});
  final List<String> urls;
  final List<String> keys;
  final int initial;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: PageView(
          controller: PageController(initialPage: initial),
          children: [
            for (final (i, u) in urls.indexed)
              InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: u.isEmpty
                      ? const SizedBox.shrink()
                      : Image(image: CachedNetImage(u, cacheKey: 'run-photo:${keys[i]}'), fit: BoxFit.contain),
                ),
              ),
          ],
        ),
      );
}

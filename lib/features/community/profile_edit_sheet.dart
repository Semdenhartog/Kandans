import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/social_service.dart';
import '../../shared/widgets.dart';
import 'avatar_picker.dart';
import 'runner_avatar.dart';

/// Je eigen profiel in Samen bewerken: foto, bio, plaats en favoriete afstand. Geeft true terug als er iets is opgeslagen.
Future<bool> openProfileEditor(BuildContext context, String nickname, ProfileExtra current) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Editor(nickname: nickname, current: current),
    ) ??
    false;

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.nickname, required this.current});
  final String nickname;
  final ProfileExtra current;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late final _bio = TextEditingController(text: widget.current.bio ?? '');
  late final _area = TextEditingController(text: widget.current.homeArea ?? '');
  late String? _fav = widget.current.favDistance;
  bool _saving = false;
  bool _photoBusy = false;
  bool _changed = false;

  SocialService get _svc => ref.read(socialServiceProvider);

  @override
  void dispose() {
    _bio.dispose();
    _area.dispose();
    super.dispose();
  }

  /// Eén keer uitleggen wat wel en niet mag, vóór de eerste foto.
  Future<bool> _rulesOk() async {
    const key = 'profile_photo_rules_seen';
    final p = await SharedPreferences.getInstance();
    if (p.getBool(key) == true) return true;
    if (!mounted) return false;
    final ok = await confirmDialog(
      context,
      title: tr('Profielfoto'),
      message: tr('Je foto is zichtbaar voor andere lopers in Samen. Kies een foto van jezelf of iets dat bij je past: '
          'geen naakt, geweld, reclame of foto’s van anderen zonder toestemming. Lopers kunnen een foto melden; '
          'na een paar meldingen wordt hij vanzelf verborgen.'),
      confirmLabel: tr('Begrepen'),
    );
    if (ok) await p.setBool(key, true);
    return ok;
  }

  Future<void> _pick(ImageSource source) async {
    if (!await _rulesOk()) return;
    final file = await ImagePicker().pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 80);
    if (file == null || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) throw Exception(tr('Deze foto is te groot. Kies een andere.'));
      await _svc.uploadPhoto(bytes);
      AvatarCache.instance.forget(widget.nickname);
      _changed = true;
      if (mounted) showMessage(context, tr('Je nieuwe foto staat erop.'));
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _photoBusy = true);
    try {
      await _svc.removePhoto();
      AvatarCache.instance.forget(widget.nickname);
      _changed = true;
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _svc.setProfile(bio: _bio.text, homeArea: _area.text, favDistance: _fav);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = AvatarCache.instance.peek(widget.nickname)?.photoUrl != null;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        // Foto is direct opgeslagen; laat het profiel dan ook verversen.
        if (didPop && _changed) AvatarCache.instance.changed.value++;
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Profiel bewerken'), style: RwText.title),
              const SizedBox(height: 16),
              Row(children: [
                RunnerAvatar(widget.nickname, size: 76),
                const SizedBox(width: 16),
                Expanded(
                  child: _photoBusy
                      ? const LinearProgressIndicator()
                      : Wrap(spacing: 8, runSpacing: 4, children: [
                          OutlinedButton.icon(
                            onPressed: () => _pick(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined, size: 18),
                            label: Text(tr('Foto kiezen')),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _pick(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined, size: 18),
                            label: Text(tr('Camera')),
                          ),
                          if (hasPhoto)
                            TextButton(onPressed: _removePhoto, child: Text(tr('Foto weghalen'))),
                        ]),
                ),
              ]),
              if (widget.current.photoHidden)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(tr('Je foto is na meldingen verborgen voor anderen. Kies een andere foto.'),
                      style: TextStyle(color: RwColors.danger, fontSize: 13)),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openAvatarPicker(context, widget.nickname),
                  icon: const Icon(Icons.brush_outlined, size: 18),
                  label: Text(tr('Icoon, kleur en omslag')),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _bio,
                maxLength: 160,
                maxLines: 3,
                minLines: 2,
                decoration: InputDecoration(labelText: tr('Over jou'), hintText: tr('Bijv. "Loop elke ochtend door het bos, op weg naar mijn eerste halve."')),
              ),
              TextField(
                controller: _area,
                maxLength: 40,
                decoration: InputDecoration(labelText: tr('Plaats of regio'), hintText: tr('Bijv. Barneveld')),
              ),
              const SizedBox(height: 4),
              Text(tr('Favoriete afstand'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in favDistanceLabels.entries)
                  ChoiceChip(
                    label: Text(tr(e.value)),
                    selected: _fav == e.key,
                    onSelected: (on) => setState(() => _fav = on ? e.key : null),
                  ),
              ]),
              const SizedBox(height: 20),
              FilledButton(onPressed: _saving ? null : _save, child: Text(tr('Opslaan'))),
            ]),
          ),
        ),
      ),
    );
  }
}

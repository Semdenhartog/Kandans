import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Offset;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/route_anim.dart';
import 'route_anim_painter.dart';
import 'package:runwise/core/motion.dart';

/// Wat de gebruiker aan de routevideo aanpast: foto erachter (met zoom/verschuiven), plek van de tekst en eigen titel.
/// De plek van de tekst wordt bewaard (pref `route_anim_layout`), de foto en titel gelden voor deze video.
class RouteAnimEditor extends ChangeNotifier {
  static const _layoutKey = 'route_anim_layout';

  ui.Image? bg;
  RouteAnimLayout layout = RouteAnimLayout.none;
  double zoom = 1;
  Offset pan = Offset.zero;
  String? title;

  /// Onderdeel dat nu versleept wordt (null = de foto of niets).
  RouteAnimPart? drag;
  bool _photoDrag = false;
  Offset _raw = Offset.zero; // ongeklikte plek tijdens het slepen, anders kun je nooit meer van de klik af
  double _zoomAtStart = 1;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    layout = RouteAnimLayout.fromJson(p.getString(_layoutKey));
  }

  void _save() => SharedPreferences.getInstance().then((p) => p.setString(_layoutKey, layout.toJson())).ignore();

  /// Geeft false als de foto niet te laden was.
  Future<bool> pickPhoto() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 2400, imageQuality: 88);
      if (file == null) return true;
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final img = (await codec.getNextFrame()).image;
      final old = bg;
      bg = img;
      zoom = 1;
      pan = Offset.zero;
      notifyListeners();
      // Het oude beeld pas loslaten als het scherm het niet meer tekent.
      Future<void>.delayed(RwMotion.normal, () => old?.dispose());
      return true;
    } catch (_) {
      return false;
    }
  }

  void clearPhoto() {
    final old = bg;
    bg = null;
    zoom = 1;
    pan = Offset.zero;
    notifyListeners();
    Future<void>.delayed(RwMotion.normal, () => old?.dispose());
  }

  void setTitle(String v) {
    title = v.isEmpty ? null : v;
    notifyListeners();
  }

  void resetLayout() {
    layout = RouteAnimLayout.none;
    _save();
    notifyListeners();
  }

  RouteAnimPart? partAt(RouteAnimStyle style, Offset p) {
    for (final part in const [RouteAnimPart.brand, RouteAnimPart.label, RouteAnimPart.stats]) {
      if (RouteAnimPainter.baseRect(style, part).shift(layout.of(part)).inflate(30).contains(p)) return part;
    }
    return null;
  }

  /// Begin van een gebaar op [at] (ontwerpmaat): een onderdeel pakken, anders de foto.
  void start(RouteAnimStyle style, Offset at) {
    drag = partAt(style, at);
    _photoDrag = drag == null && bg != null;
    _raw = drag == null ? Offset.zero : layout.of(drag!);
    _zoomAtStart = zoom;
  }

  /// [delta] in ontwerpmaat, [scale] is de knijpfactor sinds het begin van het gebaar.
  void update(RouteAnimStyle style, Offset delta, double scale) {
    final part = drag;
    if (part != null) {
      final free = layout.with_(part, _raw).moved(part, delta, RouteAnimPainter.baseRect(style, part));
      _raw = free.of(part);
      layout = free.snapped(part);
      notifyListeners();
    } else if (_photoDrag) {
      final img = bg!;
      zoom = (_zoomAtStart * scale).clamp(1.0, 4.0);
      pan = routeAnimPhotoPan(img.width.toDouble(), img.height.toDouble(), zoom, pan, delta);
      notifyListeners();
    }
  }

  void end() {
    if (drag != null) _save();
    drag = null;
    _photoDrag = false;
  }

  @override
  void dispose() {
    bg?.dispose();
    super.dispose();
  }
}

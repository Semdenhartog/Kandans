import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/appearance.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/instagram_share.dart';
import '../../domain/geo.dart';
import '../../domain/route_geometry.dart';
import '../../shared/widgets.dart';

void openShareStudio(BuildContext context, Activity a, {RunRoute? route}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ShareStudioScreen(activity: a, route: route),
  ));
}

/// De losse onderdelen die je op je deelbeeld kunt zetten en verschuiven.
enum StudioPart { line, distance, time, pace, date, text, logo }

enum StudioBackground { clear, dark, photo }

enum StudioFormat { story, post, square }

/// Plek (0–1 van het beeld, midden van het onderdeel), grootte, kleur en aan/uit van één onderdeel.
class StudioItem {
  StudioItem({required this.x, required this.y, this.scale = 1, this.on = true, this.color = 0xFFF1E9DC});
  double x;
  double y;
  double scale;
  bool on;
  int color;

  Map<String, Object> toJson() => {'x': x, 'y': y, 's': scale, 'on': on, 'c': color};

  static StudioItem fromJson(Map<String, dynamic> j, StudioItem d) => StudioItem(
        x: ((j['x'] as num?)?.toDouble() ?? d.x).clamp(0.0, 1.0).toDouble(),
        y: ((j['y'] as num?)?.toDouble() ?? d.y).clamp(0.0, 1.0).toDouble(),
        scale: ((j['s'] as num?)?.toDouble() ?? d.scale).clamp(StudioLayout.minScale, StudioLayout.maxScale).toDouble(),
        on: j['on'] as bool? ?? d.on,
        color: (j['c'] as num?)?.toInt() ?? d.color,
      );
}

/// De hele indeling van het deelbeeld. Wordt op het toestel bewaard, zodat je volgende run er meteen zo uitziet.
class StudioLayout {
  StudioLayout() : items = defaults();

  static const minScale = 0.4;
  static const maxScale = 3.0;

  final Map<StudioPart, StudioItem> items;
  double lineWidth = 5;
  bool labels = true;
  bool shadow = true;

  /// Hoe donker de foto wordt gemaakt (0 = niet, 0,7 = flink).
  double dim = 0.25;

  static Map<StudioPart, StudioItem> defaults() => {
        StudioPart.line: StudioItem(x: 0.5, y: 0.36, color: 0xFFF0DDB6),
        StudioPart.distance: StudioItem(x: 0.3, y: 0.68),
        StudioPart.time: StudioItem(x: 0.7, y: 0.68),
        StudioPart.pace: StudioItem(x: 0.5, y: 0.79, on: false),
        StudioPart.date: StudioItem(x: 0.5, y: 0.1, on: false),
        StudioPart.text: StudioItem(x: 0.5, y: 0.17, on: false),
        StudioPart.logo: StudioItem(x: 0.5, y: 0.9, color: 0xFFFFFFFF),
      };

  String encode() => jsonEncode({
        'items': {for (final e in items.entries) e.key.name: e.value.toJson()},
        'lw': lineWidth,
        'labels': labels,
        'shadow': shadow,
        'dim': dim,
      });

  /// Leest een bewaarde indeling; bij een fout of onbekende waarde gewoon de standaard.
  static StudioLayout decode(String? s) {
    final l = StudioLayout();
    if (s == null || s.isEmpty) return l;
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      final saved = (j['items'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      for (final p in StudioPart.values) {
        final v = saved[p.name];
        if (v is Map) l.items[p] = StudioItem.fromJson(v.cast<String, dynamic>(), l.items[p]!);
      }
      l.lineWidth = ((j['lw'] as num?)?.toDouble() ?? l.lineWidth).clamp(2.0, 12.0).toDouble();
      l.labels = j['labels'] as bool? ?? l.labels;
      l.shadow = j['shadow'] as bool? ?? l.shadow;
      l.dim = ((j['dim'] as num?)?.toDouble() ?? l.dim).clamp(0.0, 0.7).toDouble();
    } catch (_) {
      return StudioLayout();
    }
    return l;
  }
}

int _argb(Color c) =>
    ((c.a * 255).round() << 24) | ((c.r * 255).round() << 16) | ((c.g * 255).round() << 8) | (c.b * 255).round();

const _swatches = <int>[
  0xFFFFFFFF,
  0xFFF1E9DC,
  0xFFF0DDB6,
  0xFFD9BF92,
  0xFFE0884E,
  0xFF8CC99A,
  0xFF7FB8E6,
  0xFFEF7F78,
  0xFFE6A5D0,
  0xFF13110E,
];

/// Deelbeeld dat je zelf indeelt: de lijn van je run, afstand en tijd, op een doorzichtige of donkere
/// achtergrond of over je eigen foto. Alles is te verslepen, te vergroten en te kleuren.
class ShareStudioScreen extends StatefulWidget {
  const ShareStudioScreen({super.key, required this.activity, this.route});
  final Activity activity;
  final RunRoute? route;

  @override
  State<ShareStudioScreen> createState() => _ShareStudioScreenState();
}

class _ShareStudioScreenState extends State<ShareStudioScreen> {
  static const _layoutKey = 'share_studio_layout';
  static const _textKey = 'share_studio_text';
  static const _hideHomeKey = 'share_hide_home';

  final _canvasKey = GlobalKey();
  final _text = TextEditingController();

  StudioLayout _layout = StudioLayout();
  StudioPart? _selected;
  StudioBackground _bg = StudioBackground.clear;
  StudioFormat _format = StudioFormat.story;
  Uint8List? _photo;
  bool _hideHome = true;
  bool _busy = false;

  /// Tijdens het maken van de afbeelding: geen kader om het gekozen onderdeel.
  bool _exporting = false;

  Offset? _lastLocal;
  double _startScale = 1;

  List<LatLng> _raw = const [];

  @override
  void initState() {
    super.initState();
    final a = widget.activity;
    final line = a.hasTrack ? a.trackPolyline! : widget.route?.polyline;
    if (line != null && line.isNotEmpty) {
      try {
        _raw = decodePolyline(line);
      } catch (_) {
        _raw = const [];
      }
    }
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _layout = StudioLayout.decode(p.getString(_layoutKey));
        _text.text = p.getString(_textKey) ?? '';
        _hideHome = p.getBool(_hideHomeKey) ?? true;
      });
    }).catchError((Object _) {});
    // Staat er al een foto bij de run, dan die alvast klaarzetten als achtergrond.
    if (a.photos.isNotEmpty) {
      Supabase.instance.client.storage.from('run-photos').download(a.photos.first).then((b) {
        if (mounted && _photo == null) {
          setState(() {
            _photo = b;
            _bg = StudioBackground.photo;
          });
        }
      }).catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    SharedPreferences.getInstance().then((p) {
      p.setString(_layoutKey, _layout.encode());
      p.setString(_textKey, _text.text);
      p.setBool(_hideHomeKey, _hideHome);
    }).catchError((Object _) {});
  }

  Size get _size => switch (_format) {
        StudioFormat.story => const Size(360, 640),
        StudioFormat.post => const Size(360, 450),
        StudioFormat.square => const Size(360, 360),
      };

  List<LatLng> get _points {
    final shown = _hideHome ? trimPrivacyZone(_raw, radius: 300) : _raw;
    return shown.length < 2 ? const [] : shown;
  }

  bool _available(StudioPart p) => p != StudioPart.line || _points.isNotEmpty;

  String _name(StudioPart p) => switch (p) {
        StudioPart.line => tr('Lijn'),
        StudioPart.distance => tr('Afstand'),
        StudioPart.time => tr('Tijd'),
        StudioPart.pace => tr('Tempo'),
        StudioPart.date => tr('Datum'),
        StudioPart.text => tr('Eigen tekst'),
        StudioPart.logo => tr('Logo'),
      };

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 2160, maxHeight: 2160, imageQuality: 90);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _bg = StudioBackground.photo;
      });
    } catch (_) {
      if (mounted) showMessage(context, tr('De foto kon niet worden geladen.'), error: true);
    }
  }

  Offset? _toCanvas(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : null;
  }

  Future<Uint8List?> _png() async {
    setState(() {
      _busy = true;
      _exporting = true;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _canvasKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _exporting = false;
        });
      }
    }
  }

  Future<void> _shareSheet([Uint8List? ready]) async {
    final png = ready ?? await _png();
    if (!mounted) return;
    if (png == null) {
      showMessage(context, tr('Delen is niet gelukt. Probeer het opnieuw.'), error: true);
      return;
    }
    final a = widget.activity;
    final name = 'kadans-${a.startedAt.toLocal().toIso8601String().substring(0, 10)}.png';
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png', name: name)],
        text: '${Fmt.km(a.distanceMeters, decimals: 1)} gelopen met Kadans ${AppConfig.siteUrl}/',
      ));
    } catch (_) {
      if (mounted) showMessage(context, tr('Delen is niet gelukt. Probeer het opnieuw.'), error: true);
    }
  }

  Future<void> _toInstagram() async {
    final png = await _png();
    if (!mounted) return;
    if (png == null) {
      showMessage(context, tr('Delen is niet gelukt. Probeer het opnieuw.'), error: true);
      return;
    }
    final ok = await InstagramShare.open(png, sticker: _bg == StudioBackground.clear);
    if (!mounted || ok) return;
    showMessage(context, tr('Instagram is niet gevonden. Kies zelf een app om te delen.'));
    await _shareSheet(png);
  }

  // ---------------------------------------------------------------- het beeld

  Widget _stat(String label, String value, Color c, List<Shadow>? shadows) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_layout.labels)
            Text(
              label,
              style: TextStyle(
                fontFamily: RwFonts.body,
                color: c.withValues(alpha: 0.85),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                shadows: shadows,
              ),
            ),
          Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: RwFonts.display,
              fontFeatures: rwTnum,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: c,
              shadows: shadows,
            ),
          ),
        ],
      );

  Widget _content(StudioPart p) {
    final a = widget.activity;
    final c = Color(_layout.items[p]!.color);
    final shadows = _layout.shadow ? const [Shadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 1))] : null;
    switch (p) {
      case StudioPart.line:
        return CustomPaint(
          size: const Size(230, 230),
          painter: _StudioLinePainter(points: _points, color: c, width: _layout.lineWidth, shadow: _layout.shadow),
        );
      case StudioPart.distance:
        return _stat(tr('AFSTAND'), Fmt.km(a.distanceMeters), c, shadows);
      case StudioPart.time:
        return _stat(tr('TIJD'), Fmt.duration(a.movingTimeSeconds), c, shadows);
      case StudioPart.pace:
        return _stat(tr('TEMPO'), Fmt.pace(a.paceSecondsPerKm), c, shadows);
      case StudioPart.date:
        return Text(
          Fmt.date(a.startedAt),
          style: TextStyle(fontFamily: RwFonts.body, color: c, fontSize: 13, fontWeight: FontWeight.w600, shadows: shadows),
        );
      case StudioPart.text:
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            _text.text.trim().isEmpty ? tr('Eigen tekst') : _text.text.trim(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: RwFonts.display,
              color: c,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.1,
              shadows: shadows,
            ),
          ),
        );
      case StudioPart.logo:
        return kadansLockup(height: 28, color: c);
    }
  }

  Widget _placed(StudioPart p, Size size) {
    final it = _layout.items[p]!;
    final selected = _selected == p && !_exporting;
    return Positioned(
      left: it.x * size.width,
      top: it.y * size.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.scale(
          scale: it.scale,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selected = p),
            onScaleStart: (d) {
              _lastLocal = _toCanvas(d.focalPoint);
              _startScale = it.scale;
              setState(() => _selected = p);
            },
            onScaleUpdate: (d) {
              final now = _toCanvas(d.focalPoint);
              final last = _lastLocal;
              if (now == null || last == null) return;
              setState(() {
                it.x = (it.x + (now.dx - last.dx) / size.width).clamp(0.0, 1.0).toDouble();
                it.y = (it.y + (now.dy - last.dy) / size.height).clamp(0.0, 1.0).toDouble();
                if (d.pointerCount > 1) {
                  it.scale = (_startScale * d.scale).clamp(StudioLayout.minScale, StudioLayout.maxScale).toDouble();
                }
                _lastLocal = now;
              });
            },
            onScaleEnd: (_) => _save(),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: selected ? const Color(0xE6FFFFFF) : const Color(0x00FFFFFF), width: 1),
              ),
              child: _content(p),
            ),
          ),
        ),
      ),
    );
  }

  Widget _canvas() {
    final size = _size;
    final photo = _bg == StudioBackground.photo ? _photo : null;
    return RepaintBoundary(
      key: _canvasKey,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: ClipRect(
          child: Stack(
            children: [
              // Tik naast een onderdeel = niets meer gekozen.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selected = null),
                  child: _bg == StudioBackground.dark || (_bg == StudioBackground.photo && photo == null)
                      ? const ColoredBox(color: Color(0xFF13110E))
                      : const SizedBox.expand(),
                ),
              ),
              if (photo != null) ...[
                Positioned.fill(child: IgnorePointer(child: Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true))),
                Positioned.fill(
                  child: IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: _layout.dim))),
                ),
              ],
              for (final p in StudioPart.values)
                if (_layout.items[p]!.on && _available(p)) _placed(p, size),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ de bediening

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(text.toUpperCase(), style: RwText.overline),
      );

  Widget _swatchRow(int current, ValueChanged<int> onPick) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in _swatches)
            Semantics(
              button: true,
              selected: v == current,
              label: tr('Kleur'),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onPick(v),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(v),
                      shape: BoxShape.circle,
                      border: Border.all(color: v == current ? RwColors.accent : RwColors.border, width: v == current ? 3 : 1),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );

  List<Widget> _selectedControls(StudioPart p) {
    final it = _layout.items[p]!;
    final hue = HSVColor.fromColor(Color(it.color)).hue;
    return [
      _label('${_name(p)}: ${tr('Kleur')}'),
      _swatchRow(it.color, (v) {
        setState(() => it.color = v);
        _save();
      }),
      Row(children: [
        Expanded(flex: 2, child: Text(tr('Eigen kleur'))),
        Expanded(
          flex: 5,
          child: Slider(
            value: hue,
            max: 360,
            label: tr('Eigen kleur'),
            onChanged: (h) => setState(() => it.color = _argb(HSVColor.fromAHSV(1, h, 0.6, 1).toColor())),
            onChangeEnd: (_) => _save(),
          ),
        ),
      ]),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () {
            setState(() {
              for (final other in _layout.items.values) {
                other.color = it.color;
              }
            });
            _save();
          },
          child: Text(tr('Alles in deze kleur')),
        ),
      ),
      Row(children: [
        Expanded(flex: 2, child: Text(tr('Grootte'))),
        Expanded(
          flex: 5,
          child: Slider(
            value: it.scale,
            min: StudioLayout.minScale,
            max: StudioLayout.maxScale,
            label: tr('Grootte'),
            onChanged: (v) => setState(() => it.scale = v),
            onChangeEnd: (_) => _save(),
          ),
        ),
      ]),
      if (p == StudioPart.line)
        Row(children: [
          Expanded(flex: 2, child: Text(tr('Dikte van de lijn'))),
          Expanded(
            flex: 5,
            child: Slider(
              value: _layout.lineWidth,
              min: 2,
              max: 12,
              label: tr('Dikte van de lijn'),
              onChanged: (v) => setState(() => _layout.lineWidth = v),
              onChangeEnd: (_) => _save(),
            ),
          ),
        ]),
      if (p == StudioPart.text)
        TextField(
          controller: _text,
          maxLength: 60,
          decoration: InputDecoration(labelText: tr('Typ je eigen tekst')),
          onChanged: (_) => setState(() {}),
          onEditingComplete: () {
            FocusScope.of(context).unfocus();
            _save();
          },
        ),
    ];
  }

  Widget _controls() {
    final sel = _selected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      children: [
        _label(tr('Achtergrond')),
        SegmentedButton<StudioBackground>(
          segments: [
            ButtonSegment(value: StudioBackground.clear, label: Text(tr('Doorzichtig'))),
            ButtonSegment(value: StudioBackground.dark, label: Text(tr('Donker'))),
            ButtonSegment(value: StudioBackground.photo, label: Text(tr('Foto'))),
          ],
          selected: {_bg},
          onSelectionChanged: (s) {
            setState(() => _bg = s.first);
            if (s.first == StudioBackground.photo && _photo == null) _pickPhoto(ImageSource.gallery);
          },
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pickPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_photo == null ? tr('Foto kiezen') : tr('Foto wijzigen')),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: tr('Camera'),
            onPressed: () => _pickPhoto(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
          ),
        ]),
        if (_bg == StudioBackground.photo && _photo != null)
          Row(children: [
            Expanded(flex: 2, child: Text(tr('Foto donkerder'))),
            Expanded(
              flex: 5,
              child: Slider(
                value: _layout.dim,
                max: 0.7,
                label: tr('Foto donkerder'),
                onChanged: (v) => setState(() => _layout.dim = v),
                onChangeEnd: (_) => _save(),
              ),
            ),
          ]),
        _label(tr('Formaat')),
        SegmentedButton<StudioFormat>(
          segments: [
            ButtonSegment(value: StudioFormat.story, label: Text(tr('Verhaal'))),
            ButtonSegment(value: StudioFormat.post, label: Text(tr('Bericht'))),
            ButtonSegment(value: StudioFormat.square, label: Text(tr('Vierkant'))),
          ],
          selected: {_format},
          onSelectionChanged: (s) => setState(() => _format = s.first),
        ),
        _label(tr('Onderdelen')),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final p in StudioPart.values)
              if (_available(p))
                FilterChip(
                  label: Text(_name(p)),
                  selected: _layout.items[p]!.on,
                  onSelected: (on) {
                    setState(() {
                      _layout.items[p]!.on = on;
                      _selected = on ? p : (_selected == p ? null : _selected);
                    });
                    _save();
                  },
                ),
          ],
        ),
        if (sel != null && _layout.items[sel]!.on && _available(sel))
          ..._selectedControls(sel)
        else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              tr('Tik op een onderdeel om het te kiezen. Sleep om te verplaatsen, knijp om te vergroten.'),
              style: TextStyle(color: RwColors.muted, fontSize: 13),
            ),
          ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _layout.labels,
          onChanged: (v) {
            setState(() => _layout.labels = v);
            _save();
          },
          title: Text(tr('Labels boven de cijfers')),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _layout.shadow,
          onChanged: (v) {
            setState(() => _layout.shadow = v);
            _save();
          },
          title: Text(tr('Schaduw voor leesbaarheid')),
        ),
        if (_raw.length > 1)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hideHome,
            onChanged: (v) {
              setState(() => _hideHome = v);
              _save();
            },
            title: Text(tr('Verberg waar je woont')),
            subtitle: Text(tr('Laat de eerste en laatste 300 m van je route weg')),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _layout = StudioLayout();
                _selected = null;
              });
              _save();
            },
            icon: const Icon(Icons.restart_alt),
            label: Text(tr('Opnieuw indelen')),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Maak je eigen deelbeeld'))),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Center(
                  child: FittedBox(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(RwRadius.s),
                      // Ruitjes achter het beeld laten zien wat doorzichtig blijft; ze komen niet in de afbeelding.
                      child: CustomPaint(painter: const _CheckerPainter(), child: _canvas()),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(flex: 4, child: _controls()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _toInstagram,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(tr('Naar Instagram')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _shareSheet(),
                    icon: const Icon(Icons.ios_share),
                    label: Text(tr('Delen of opslaan')),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// De lijn van je run, passend in het vak, in één kleur.
class _StudioLinePainter extends CustomPainter {
  _StudioLinePainter({required this.points, required this.color, required this.width, required this.shadow});
  final List<LatLng> points;
  final Color color;
  final double width;
  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    var minLat = points.first.lat, maxLat = points.first.lat, minLon = points.first.lon, maxLon = points.first.lon;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    final lonScale = math.cos(((minLat + maxLat) / 2) * math.pi / 180);
    final w = math.max((maxLon - minLon) * lonScale, 1e-9);
    final h = math.max(maxLat - minLat, 1e-9);
    const pad = 10.0;
    final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x = ox + (p.lon - minLon) * lonScale * scale;
      final y = oy + (maxLat - p.lat) * scale;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    if (shadow) {
      canvas.drawPath(
        path.shift(const Offset(0, 1)),
        Paint()
          ..color = const Color(0x73000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _StudioLinePainter old) =>
      old.points != points || old.color != color || old.width != width || old.shadow != shadow;
}

/// Ruitjes zoals in een fotoprogramma: hier is het beeld doorzichtig.
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 20.0;
    final a = Paint()..color = const Color(0xFF2B251F);
    final b = Paint()..color = const Color(0xFF3A332B);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), (x + y).isEven ? a : b);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter old) => false;
}

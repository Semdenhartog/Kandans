import 'dart:async';

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../shared/art/landscape.dart';

/// Profielplaatje in Samen: een icoon in een eigen kleur met een gouden rand.
/// Zonder keuze: de eerste letter van de bijnaam.
class AvatarStyle {
  const AvatarStyle({this.icon, this.color, this.cover});
  final String? icon;
  final int? color;
  final String? cover;
}

const avatarIcons = <String, IconData>{
  'run': Icons.directions_run,
  'bolt': Icons.bolt,
  'fire': Icons.local_fire_department_outlined,
  'leaf': Icons.eco_outlined,
  'sun': Icons.wb_sunny_outlined,
  'moon': Icons.nightlight_outlined,
  'mountain': Icons.terrain_outlined,
  'wave': Icons.waves,
  'star': Icons.star_outline,
  'heart': Icons.favorite_border,
  'paw': Icons.pets_outlined,
  'crown': Icons.workspace_premium_outlined,
  'flag': Icons.flag_outlined,
  'tree': Icons.park_outlined,
  'snow': Icons.ac_unit,
  'coffee': Icons.coffee_outlined,
};

const avatarColors = <Color>[
  Color(0xFFFD8A26), // oranje (Kadans)
  Color(0xFF3FAE7A), // groen
  Color(0xFF4C8DFF), // blauw
  Color(0xFFA77BC9), // hei-paars
  Color(0xFFE5484D), // rood
  Color(0xFFD9A441), // goud
  Color(0xFF2BB3B1), // zeegroen
  Color(0xFF8A8F98), // grijs
];

/// Haalt plaatjes op in groepjes (één verzoek voor een hele lijst).
class AvatarCache {
  AvatarCache._();
  static final instance = AvatarCache._();

  final _known = <String, AvatarStyle>{};
  final _waiting = <String, List<Completer<AvatarStyle>>>{};
  final changed = ValueNotifier<int>(0);
  Timer? _flush;

  AvatarStyle? peek(String nick) => _known[nick.toLowerCase()];

  Future<AvatarStyle> get(String nick) {
    final key = nick.toLowerCase();
    final k = _known[key];
    if (k != null) return Future.value(k);
    final c = Completer<AvatarStyle>();
    (_waiting[key] ??= []).add(c);
    _flush ??= Timer(const Duration(milliseconds: 60), _load);
    return c.future;
  }

  void setMine(String nick, AvatarStyle s) {
    _known[nick.toLowerCase()] = s;
    changed.value++;
  }

  Future<void> _load() async {
    _flush = null;
    final batch = Map.of(_waiting);
    _waiting.clear();
    final found = <String, AvatarStyle>{};
    try {
      final rows = await Supabase.instance.client.rpc('social_avatars', params: {'p_nicknames': batch.keys.toList()}) as List;
      for (final r in rows.cast<Map<String, dynamic>>()) {
        found[(r['nickname'] as String).toLowerCase()] = AvatarStyle(
          icon: r['avatar_icon'] as String?,
          color: (r['avatar_color'] as num?)?.toInt(),
          cover: r['cover'] as String?,
        );
      }
    } catch (_) {
      // Geen verbinding of nog niet ingelogd: dan de letter.
    }
    for (final e in batch.entries) {
      final s = found[e.key] ?? const AvatarStyle();
      _known[e.key] = s;
      for (final c in e.value) {
        c.complete(s);
      }
    }
  }
}

class RunnerAvatar extends StatefulWidget {
  const RunnerAvatar(this.name, {super.key, this.size = 36, this.style});
  final String name;
  final double size;

  /// Vaste stijl (bijvoorbeeld in de kiezer); anders wordt hij opgehaald.
  final AvatarStyle? style;

  @override
  State<RunnerAvatar> createState() => _RunnerAvatarState();
}

class _RunnerAvatarState extends State<RunnerAvatar> {
  AvatarStyle? _s;

  @override
  void initState() {
    super.initState();
    _fetch();
    AvatarCache.instance.changed.addListener(_refresh);
  }

  @override
  void didUpdateWidget(RunnerAvatar old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) _fetch();
  }

  @override
  void dispose() {
    AvatarCache.instance.changed.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() => _s = AvatarCache.instance.peek(widget.name) ?? _s);
  }

  void _fetch() {
    if (widget.style != null || widget.name.isEmpty) return;
    _s = AvatarCache.instance.peek(widget.name);
    if (_s != null) return;
    AvatarCache.instance.get(widget.name).then((s) {
      if (mounted) setState(() => _s = s);
    }).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.style ?? _s;
    final size = widget.size;
    final icon = avatarIcons[s?.icon];
    final base = s?.color == null ? null : avatarColors[s!.color!.clamp(0, avatarColors.length - 1)];
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [RwColors.accentLight, RwColors.accentDeep, RwColors.accentLight, RwColors.accentDeep, RwColors.accentLight]),
      ),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: base == null
              ? LinearGradient(colors: [RwColors.accentLight, RwColors.accentDeep])
              : RadialGradient(center: const Alignment(-0.3, -0.4), colors: [Color.lerp(base, Colors.white, 0.25)!, base, Color.lerp(base, Colors.black, 0.3)!]),
        ),
        child: icon != null
            ? Icon(icon, size: size * 0.5, color: Colors.white)
            : Text(widget.name.isEmpty ? '?' : widget.name.characters.first.toUpperCase(),
                style: TextStyle(color: base == null ? RwColors.accentDark : Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.4)),
      ),
    );
  }
}

/// Maand die bij een omslagkeuze hoort (voor het seizoenslandschap).
DateTime coverDate(String? cover) {
  final y = DateTime.now().year;
  return switch (cover) {
    'winter' => DateTime(y, 1, 15),
    'lente' => DateTime(y, 4, 15),
    'zomer' => DateTime(y, 7, 15),
    'hei' => DateTime(y, 8, 15),
    'herfst' => DateTime(y, 10, 15),
    'mist' => DateTime(y, 11, 15),
    _ => DateTime.now(),
  };
}

const coverChoices = ['auto', 'winter', 'lente', 'zomer', 'hei', 'herfst', 'mist'];

/// Omslag boven een profiel: het seizoenslandschap dat de loper koos.
class ProfileCover extends StatefulWidget {
  const ProfileCover({super.key, required this.nickname, this.height = 96, this.style});
  final String nickname;
  final double height;
  final AvatarStyle? style;

  @override
  State<ProfileCover> createState() => _ProfileCoverState();
}

class _ProfileCoverState extends State<ProfileCover> {
  AvatarStyle? _s;

  @override
  void initState() {
    super.initState();
    _s = AvatarCache.instance.peek(widget.nickname);
    if (_s == null) {
      AvatarCache.instance.get(widget.nickname).then((s) {
        if (mounted) setState(() => _s = s);
      }).catchError((Object _) {});
    }
    AvatarCache.instance.changed.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() => _s = AvatarCache.instance.peek(widget.nickname) ?? _s);
  }

  @override
  void dispose() {
    AvatarCache.instance.changed.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [RwColors.accent.withValues(alpha: 0.2), RwColors.surface],
            ),
          ),
          child: KadansLandscape(date: coverDate((widget.style ?? _s)?.cover), opacity: 0.95),
        ),
      );
}

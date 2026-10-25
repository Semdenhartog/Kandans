import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/badges.dart' as bd;
import '../../shared/widgets.dart';

void openBadges(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BadgesScreen()));
}

IconData badgeIcon(String name) => switch (name) {
      'flag' => Icons.flag,
      'looks_5' => Icons.looks_5,
      'filter_9_plus' => Icons.filter_9_plus,
      'military_tech' => Icons.military_tech,
      'emoji_events' => Icons.emoji_events,
      'directions_run' => Icons.directions_run,
      'route' => Icons.route,
      'public' => Icons.public,
      'local_fire_department' => Icons.local_fire_department,
      'wb_twilight' => Icons.wb_twilight,
      'nightlight' => Icons.nightlight,
      'terrain' => Icons.terrain,
      'explore' => Icons.explore,
      'air' => Icons.air,
      'storm' => Icons.storm,
      'ac_unit' => Icons.ac_unit,
      'water_drop' => Icons.water_drop,
      'bolt' => Icons.bolt,
      'wb_sunny' => Icons.wb_sunny,
      'light_mode' => Icons.light_mode,
      'park' => Icons.park,
      'celebration' => Icons.celebration,
      'eco' => Icons.eco,
      'event_repeat' => Icons.event_repeat,
      'calendar_month' => Icons.calendar_month,
      'cake' => Icons.cake,
      'map' => Icons.map,
      'travel_explore' => Icons.travel_explore,
      'luggage' => Icons.luggage,
      'landscape' => Icons.landscape,
      _ => Icons.star,
    };

/// Badges en mijlpalen (zoals de awards in Nike Run Club), met eigen RunWise-weerbadges.
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final all = bd.computeBadges(runs);
    final earned = all.where((b) => b.earned).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Badges')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('$earned van ${all.length} verdiend',
              style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Tik op een badge voor meer uitleg.', style: TextStyle(color: RwColors.subtle)),
          for (final cat in bd.BadgeCategory.values) ...[
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Text(cat.title, style: RwText.overline)),
              Text(
                '${all.where((b) => b.category == cat && b.earned).length}/${all.where((b) => b.category == cat).length}',
                style: const TextStyle(color: RwColors.subtle, fontSize: 12, fontFeatures: rwTnum),
              ),
            ]),
            if (cat.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(cat.subtitle!, style: const TextStyle(color: RwColors.subtle, fontSize: 12)),
            ],
            const SizedBox(height: 10),
            _Grid(badges: [for (final b in all) if (b.category == cat) b]),
          ],
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.badges});
  final List<bd.Badge> badges;

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.0,
        children: [for (final b in badges) BadgeTile(badge: b)],
      );
}

class BadgeTile extends StatelessWidget {
  const BadgeTile({super.key, required this.badge, this.size = 64});
  final bd.Badge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = badge;
    final color = b.weather ? const Color(0xFF5AA9FF) : RwColors.accent;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MedalShowcase(badge: b, color: color),
                const SizedBox(height: 8),
                Text(b.title, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(b.description, textAlign: TextAlign.center, style: const TextStyle(color: RwColors.muted)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: (b.earned ? color : RwColors.subtle).withValues(alpha: 0.12),
                    border: Border.all(color: (b.earned ? color : RwColors.subtle).withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    b.earned ? 'Verdiend op ${Fmt.dateLong(b.earnedAt!)}' : (b.progress > 0 ? '${(b.progress * 100).round()}% op weg' : 'Nog niet verdiend'),
                    style: TextStyle(color: b.earned ? color : RwColors.subtle, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      child: Column(
        children: [
          _Medal(badge: b, size: size, color: color),
          const SizedBox(height: 6),
          Text(b.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: b.earned ? RwColors.text : RwColors.subtle)),
        ],
      ),
    );
  }
}

class _Medal extends StatefulWidget {
  const _Medal({required this.badge, required this.size, required this.color});
  final bd.Badge badge;
  final double size;
  final Color color;

  @override
  State<_Medal> createState() => _MedalState();
}

/// Een echte medaille: geslepen metaal (kegelverloop), een verzonken binnenring,
/// een gegraveerd icoon en af en toe een lichtglans die eroverheen trekt.
class _MedalState extends State<_Medal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200));

  @override
  void initState() {
    super.initState();
    final still = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.badge.earned && !still) {
      // Iedere medaille op een eigen moment, zodat ze niet allemaal tegelijk glanzen.
      _c.value = (widget.badge.id.hashCode % 100) / 100;
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color _shade(Color c, double l) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness + l).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.badge;
    final size = widget.size;
    final color = widget.color;
    if (!b.earned) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          if (b.progress > 0)
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(value: b.progress, strokeWidth: 3, color: color.withValues(alpha: 0.7), backgroundColor: RwColors.bar),
            ),
          Container(
            width: size - 8,
            height: size - 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RwColors.bar.withValues(alpha: 0.4),
              border: Border.all(color: RwColors.border, width: 1.5),
            ),
            child: Icon(badgeIcon(b.icon), size: size * 0.42, color: RwColors.subtle),
          ),
        ]),
      );
    }
    final light = _shade(color, 0.28), dark = _shade(color, -0.22), deep = _shade(color, -0.36);
    final metal = SweepGradient(colors: [light, color, dark, color, light, color, dark, light]);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: size * 0.28, spreadRadius: -2),
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 6, offset: const Offset(0, 3)),
          ],
        ),
        child: ClipOval(
          child: Stack(fit: StackFit.expand, children: [
            DecoratedBox(decoration: BoxDecoration(gradient: metal)),
            Padding(
              padding: EdgeInsets.all(size * 0.1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(center: const Alignment(-0.3, -0.4), radius: 1.1, colors: [color, dark, deep]),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.25), width: 1),
                ),
                child: Center(
                  child: Icon(badgeIcon(b.icon), size: size * 0.4, color: Colors.white.withValues(alpha: 0.92), shadows: [
                    Shadow(color: Colors.black.withValues(alpha: 0.45), offset: const Offset(0, 1.2), blurRadius: 1.5),
                  ]),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) {
                // Glans alleen in het eerste deel van de cyclus.
                final t = (_c.value / 0.3).clamp(0.0, 1.0);
                if (t <= 0 || t >= 1) return const SizedBox.shrink();
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1.6 + 3.2 * t, -1),
                      end: Alignment(-1.0 + 3.2 * t, 1),
                      colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.45), Colors.white.withValues(alpha: 0)],
                    ),
                  ),
                );
              },
            ),
          ]),
        ),
      ),
    );
  }
}

/// Banner op het overzicht na je run: nieuw verdiende badges.
class NewBadgesBanner extends StatelessWidget {
  const NewBadgesBanner({super.key, required this.badges});
  final List<bd.Badge> badges;

  @override
  Widget build(BuildContext context) => RwCard(
        title: badges.length == 1 ? 'NIEUWE BADGE' : '${badges.length} NIEUWE BADGES',
        child: SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: badges.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(width: 80, child: BadgeTile(badge: badges[i], size: 56)),
          ),
        ),
      );
}


/// De medaille groot in beeld: draait bij openen een keer rond en staat in een stralenkrans.
class _MedalShowcase extends StatefulWidget {
  const _MedalShowcase({required this.badge, required this.color});
  final bd.Badge badge;
  final Color color;

  @override
  State<_MedalShowcase> createState() => _MedalShowcaseState();
}

class _MedalShowcaseState extends State<_MedalShowcase> with SingleTickerProviderStateMixin {
  late final _rays = AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void initState() {
    super.initState();
    if (widget.badge.earned && !WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      _rays.repeat();
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _rays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.badge;
    return SizedBox(
      width: 220,
      height: 190,
      child: Stack(alignment: Alignment.center, children: [
        if (b.earned)
          AnimatedBuilder(
            animation: _rays,
            builder: (_, _) => Transform.rotate(
              angle: _rays.value * 2 * math.pi,
              child: CustomPaint(size: const Size(220, 220), painter: _RaysPainter(widget.color)),
            ),
          ),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: b.earned ? 0 : 1, end: 1),
          duration: const Duration(milliseconds: 1400),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY((1 - t) * 2 * math.pi)
              ..scale(0.7 + 0.3 * t, 0.7 + 0.3 * t),
            child: child,
          ),
          child: _Medal(badge: b, size: 130, color: widget.color),
        ),
      ]),
    );
  }
}

class _RaysPainter extends CustomPainter {
  _RaysPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r * 0.75,
      Paint()..shader = RadialGradient(colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r * 0.75)),
    );
    final p = Paint()..shader = RadialGradient(colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r));
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a - 0.09) * r, c.dy + math.sin(a - 0.09) * r)
        ..lineTo(c.dx + math.cos(a + 0.09) * r, c.dy + math.sin(a + 0.09) * r)
        ..close();
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => old.color != color;
}

import 'package:flutter/material.dart';
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
    final normal = all.where((b) => !b.weather).toList();
    final weather = all.where((b) => b.weather).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Badges')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('$earned van ${all.length} verdiend',
              style: const TextStyle(fontFamily: RwFonts.display, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Tik op een badge voor meer uitleg.', style: TextStyle(color: RwColors.subtle)),
          const SizedBox(height: 16),
          _Grid(badges: normal),
          const SizedBox(height: 20),
          const Text('WEERBADGES', style: TextStyle(fontSize: 13, color: RwColors.subtle, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
          const SizedBox(height: 4),
          const Text('Alleen in RunWise: voor lopen in bijzonder weer.', style: TextStyle(color: RwColors.subtle, fontSize: 12)),
          const SizedBox(height: 10),
          _Grid(badges: weather),
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
                _Medal(badge: b, size: 96, color: color),
                const SizedBox(height: 12),
                Text(b.title, style: const TextStyle(fontFamily: RwFonts.display, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(b.description, textAlign: TextAlign.center, style: const TextStyle(color: RwColors.muted)),
                const SizedBox(height: 8),
                Text(
                  b.earned ? 'Verdiend op ${Fmt.dateLong(b.earnedAt!)}' : (b.progress > 0 ? '${(b.progress * 100).round()}% op weg' : 'Nog niet verdiend'),
                  style: TextStyle(color: b.earned ? color : RwColors.subtle, fontWeight: FontWeight.w600),
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

class _Medal extends StatelessWidget {
  const _Medal({required this.badge, required this.size, required this.color});
  final bd.Badge badge;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final b = badge;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!b.earned && b.progress > 0)
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
              color: b.earned ? color.withValues(alpha: 0.18) : RwColors.bar.withValues(alpha: 0.4),
              border: Border.all(color: b.earned ? color : RwColors.border, width: 2),
            ),
            child: Icon(badgeIcon(b.icon), size: size * 0.45, color: b.earned ? color : RwColors.subtle),
          ),
        ],
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

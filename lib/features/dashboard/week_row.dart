import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/geo.dart';
import '../../domain/start_time_scoring.dart';
import '../../shared/widgets.dart';
import '../../domain/training_plan.dart';
import '../../shared/art/wolkje.dart';
import '../planner/this_week_screen.dart';

class WeekRow extends ConsumerWidget {
  const WeekRow({required this.scores, required this.type});
  final List<StartTimeScore> scores;
  final TrainingType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider).value ?? <PlanSession>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next = [
      for (final p in plan)
        if (!p.date.isBefore(today) && p.date.difference(today).inDays < 7) p,
    ]..sort((a, b) => a.date.compareTo(b.date));
    const days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
    String dayLabel(DateTime d) {
      final diff = d.difference(today).inDays;
      final base = '${days[d.weekday - 1]} ${d.day}';
      return diff == 0 ? '$base · vandaag' : diff == 1 ? '$base · morgen' : base;
    }

    DateTime? bestOn(DateTime d) {
      StartTimeScore? best;
      for (final s in scores) {
        if (s.start.year == d.year && s.start.month == d.month && s.start.day == d.day && s.start.isAfter(now)) {
          if (best == null || s.score > best.score) best = s;
        }
      }
      return best?.start;
    }

    final head = Row(children: [
      Expanded(child: SectionLabel('Deze week', number: 3)),
      TextButton(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: RwColors.accentDeep),
        onPressed: () => openThisWeek(context),
        child: Text(tr('Alles →')),
      ),
    ]);
    if (next.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        SizedBox(height: 6),
        RwCard(
          onTap: () => openThisWeek(context),
          child: Row(children: [
            Icon(Icons.date_range_outlined, color: RwColors.accentDeep),
            SizedBox(width: 12),
            Expanded(child: Text(tr('Bekijk je week: de beste momenten per dag.'), style: TextStyle(color: RwColors.muted))),
            Icon(Icons.chevron_right, color: RwColors.subtle),
          ]),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      SizedBox(height: 6),
      LayoutBuilder(builder: (context, c) {
        final cardW = math.min(170.0, c.maxWidth * 0.42);
        final big = MediaQuery.textScalerOf(context).scale(1) > 1.25;
        return SizedBox(
          height: big ? 196 : 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: next.length,
            separatorBuilder: (_, _) => SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = next[i];
              final first = i == 0;
              final t = bestOn(p.date);
              final fg = first ? Color(0xFFF1E9DC) : RwColors.text;
              final soft = first ? Color(0xFFBDB1A0) : RwColors.muted;
              return GestureDetector(
 behavior: HitTestBehavior.opaque,
                onTap: () => openThisWeek(context),
                child: Container(
                  width: cardW,
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: first ? Color(0xFF211A14) : RwColors.surface,
                    borderRadius: BorderRadius.circular(RwRadius.m),
                    border: Border.all(color: first ? Color(0xFF211A14) : RwColors.hairline),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(dayLabel(p.date).toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: SectionLabel.style(color: soft).copyWith(fontSize: 11)),
                    Spacer(),
                    Text(t == null ? (p.distanceMeters == null ? '–' : Fmt.km(p.distanceMeters!)) : Fmt.time(t),
                        maxLines: 1,
                        style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 26, fontWeight: FontWeight.w700, color: fg)),
                    Spacer(),
                    Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, height: 1.3, color: soft)),
                  ]),
                ),
              );
            },
          ),
        );
      }),
    ]);
  }
}

/// "vraag Cloudy → tik hier" in handschrift, met een getekende pijl naar Wolkje. Het hele vlak gaat naar de coach.

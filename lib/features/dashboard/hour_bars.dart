import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/start_time_scoring.dart';
import 'package:runwise/core/motion.dart';

/// Dag in woorden: Vandaag, Morgen of de datum.
String dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Vandaag';
  if (diff == 1) return 'Morgen';
  return Fmt.date(t);
}

class HourBars extends StatefulWidget {
  const HourBars({
    required this.scores,
    required this.best,
    required this.selected,
    required this.onTap,
  });

  final List<StartTimeScore> scores;
  final StartTimeScore best;
  final DateTime selected;
  final ValueChanged<StartTimeScore> onTap;

  @override
  State<HourBars> createState() => HourBarsState();
}

class HourBarsState extends State<HourBars> {
  /// Breedte van één uur: staafje (30) + tussenruimte (6).
  static const double _step = 36;
  final _scroll = ScrollController();
  int _last = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Vasthouden en slepen (zoals op kadans.fit): het uur onder je vinger wordt gekozen, met een tikje per uur.
  void _scrub(double dx) {
    final scores = widget.scores;
    if (scores.isEmpty || !_scroll.hasClients) return;
    final i = ((dx + _scroll.offset) / _step).floor().clamp(0, scores.length - 1);
    if (i == _last) return;
    _last = i;
    HapticFeedback.selectionClick();
    widget.onTap(scores[i]);
  }

  @override
  Widget build(BuildContext context) {
    final scores = widget.scores;
    final best = widget.best;
    final selected = widget.selected;
    final onTap = widget.onTap;
    return SizedBox(
      height: 146,
      child: GestureDetector(
        onLongPressStart: (d) {
          _last = -1;
          _scrub(d.localPosition.dx);
        },
        onLongPressMoveUpdate: (d) => _scrub(d.localPosition.dx),
        child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        itemCount: scores.length,
        separatorBuilder: (_, _) => SizedBox(width: 6),
        itemBuilder: (context, i) {
          final s = scores[i];
          final isSel = s.start == selected;
          final isBest = s.start.day == best.start.day && s.start.hour == best.start.hour;
          final newDay = i == 0 || scores[i - 1].start.day != s.start.day;
          // Voor TalkBack: elk staafje als knop met tijd en score, in plaats van alleen het uur.
          return Semantics(
            button: true,
            selected: isSel,
            excludeSemantics: true,
            label: '${dayLabel(s.start)} ${Fmt.time(s.start)}, score ${s.score}, ${s.verdict.toLowerCase()}${isBest ? ', beste moment' : ''}',
            child: GestureDetector(
 behavior: HitTestBehavior.opaque,
            onTap: () {
              if (!isSel) HapticFeedback.selectionClick();
              onTap(s);
            },
            child: SizedBox(
              width: 30,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    newDay ? (dayLabel(s.start) == 'Vandaag' ? 'nu' : dayLabel(s.start).toLowerCase()) : '',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(fontSize: 11, color: RwColors.accent, fontWeight: FontWeight.w700),
                  ),
                  // Score boven het gekozen en het beste uur, zodat je niet hoeft te raden.
                  Text(
                    isSel || isBest ? '${s.score}' : '',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontFeatures: rwTnum,
                      fontWeight: FontWeight.w800,
                      color: isBest ? RwColors.accent : RwColors.text,
                    ),
                  ),
                  SizedBox(height: 2),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      // Staafjes groeien bij openen één voor één omhoog; het beste uur gloeit.
                      child: TweenAnimationBuilder<double>(
                        // Bij "minder beweging" (Android-toegankelijkheid) meteen op hoogte.
                        tween: Tween(begin: MediaQuery.disableAnimationsOf(context) ? (s.score.clamp(5, 100)) / 100 : 0, end: (s.score.clamp(5, 100)) / 100),
                        duration: Duration(milliseconds: 500 + 35 * i.clamp(0, 16)),
                        curve: Curves.easeOutCubic,
                        builder: (_, h, _) => FractionallySizedBox(
                          heightFactor: h,
                          // Kleur loopt vloeiend over als je een ander uur kiest.
                          child: AnimatedContainer(
                            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : RwMotion.fast,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: isBest
                                    ? [RwColors.accentLight, RwColors.accent, RwColors.accentDeep]
                                    : isSel
                                        ? [RwColors.subtle, RwColors.muted]
                                        // Kleur volgt de score: goede uren warmer, matige uren vager.
                                        : s.score >= 80
                                            ? [RwColors.accentLight.withValues(alpha: 0.75), RwColors.accent.withValues(alpha: 0.6)]
                                            : s.score >= 60
                                                ? [RwColors.border, RwColors.bar]
                                                : [RwColors.bar.withValues(alpha: 0.55), RwColors.bar.withValues(alpha: 0.45)],
                              ),
                              boxShadow: isBest ? [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, spreadRadius: -2)] : null,
                              borderRadius: BorderRadius.circular(RwRadius.s),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    s.start.hour.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 11,
                      color: isSel ? RwColors.text : RwColors.subtle,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
          );
        },
      ),
      ),
    );
  }
}

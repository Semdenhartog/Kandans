import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Componenten uit de Figma-pagina "Componenten".

/// Witte kaart met rand en hoek 24 (basis van bijna alle blokken).
class RwPanel extends StatelessWidget {
  const RwPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = RwColors.oppervlak,
    this.border = true,
    this.radius = RwRadius.r24,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool border;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border ? const BorderSide(color: RwColors.rand) : BorderSide.none,
    );
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Paginakop: grote titel met ondertitel en optionele ronde knop rechts.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.action});

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: RwColors.tekst)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: const TextStyle(fontSize: 13, color: RwColors.tekstZacht)),
              ],
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}

/// Ronde knop van 44×44 (Meldingen, Nieuwe route).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.size = 44,
    this.iconSize = 20,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final double size;
  final double iconSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: filled ? RwColors.primair : RwColors.oppervlak,
      shape: CircleBorder(side: filled ? BorderSide.none : const BorderSide(color: RwColors.rand)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: filled ? RwColors.opPrimair : RwColors.tekst),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Oranje pil, bijv. "Score 92" of "PRO".
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.small = false, this.color = RwColors.oranje});

  final String text;
  final bool small;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(RwRadius.rond)),
      child: Text(
        text,
        style: TextStyle(
          color: RwColors.opPrimair,
          fontWeight: FontWeight.w700,
          fontSize: small ? 10 : 12,
          letterSpacing: small ? 0.4 : 0,
        ),
      ),
    );
  }
}

/// Weer-tegel: icoon, waarde en label.
class WeatherTile extends StatelessWidget {
  const WeatherTile({super.key, required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RwColors.oppervlak,
        border: Border.all(color: RwColors.rand),
        borderRadius: BorderRadius.circular(RwRadius.r16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: RwColors.primair),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: RwColors.tekst)),
          ),
          const SizedBox(height: 8),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: RwColors.tekstZacht)),
        ],
      ),
    );
  }
}

/// Tijdslot: staaf in de tijdlijn (score 0–100), oranje als het de beste is.
class TimeSlotBar extends StatelessWidget {
  const TimeSlotBar({
    super.key,
    required this.label,
    required this.score,
    this.best = false,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final int score;
  final bool best;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final h = 80 * (score.clamp(8, 100) / 100);
    final color = best ? RwColors.oranje : (selected ? RwColors.primair : RwColors.slotNormaal);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 80,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 20,
                  height: h,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(RwRadius.r8)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: best ? FontWeight.w700 : FontWeight.w500,
                color: best ? RwColors.oranje : RwColors.tekstZacht,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filterchip.
class RwChip extends StatelessWidget {
  const RwChip({super.key, required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? RwColors.primair : RwColors.oppervlak,
      shape: StadiumBorder(side: active ? BorderSide.none : const BorderSide(color: RwColors.rand)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? RwColors.opPrimair : RwColors.tekst,
            ),
          ),
        ),
      ),
    );
  }
}

/// Vierkant icoonvlak met zachte kleur (Training van vandaag, Routekaart).
class IconBox extends StatelessWidget {
  const IconBox({
    super.key,
    required this.icon,
    this.size = 48,
    this.iconSize = 24,
    this.background = RwColors.oranjeZacht,
    this.color = RwColors.oranje,
    this.circle = false,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color background;
  final Color color;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: circle ? null : BorderRadius.circular(RwRadius.r16),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

/// Score-blokje rechts op een routekaart.
class ScoreBlock extends StatelessWidget {
  const ScoreBlock(this.score, {super.key});
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: RwColors.oranjeZacht, borderRadius: BorderRadius.circular(RwRadius.r12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$score',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: RwColors.oranje)),
          const Text('score', style: TextStyle(fontSize: 10, color: RwColors.oranje)),
        ],
      ),
    );
  }
}

/// Regel met vinkje (voordelen op de paywall).
class BenefitRow extends StatelessWidget {
  const BenefitRow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(color: RwColors.primairZacht, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 14, color: RwColors.primair),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 14, height: 20 / 14, color: RwColors.tekst)),
        ),
      ],
    );
  }
}

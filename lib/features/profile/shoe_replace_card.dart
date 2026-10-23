import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/shoe_shop.dart';
import '../../shared/widgets.dart';

/// Welke winkel achter "Bekijk nieuwe schoenen" zit (instelbaar in Supabase, zie [ShoeShop]).
final shoeShopProvider = FutureProvider<ShoeShop>((ref) async {
  try {
    final rows = await ref
        .watch(supabaseProvider)
        .from('model_config')
        .select('key, value')
        .inFilter('key', ['shoe_shop_name', 'shoe_shop_url', 'shoe_shop_partner']);
    return ShoeShop.fromConfig({for (final r in rows) r['key'] as String: r['value'] as String});
  } catch (_) {
    return ShoeShop.fallback;
  }
});

const _gold = Color(0xFFD9B45A);
const _goldDeep = Color(0xFF8A6A22);

/// Luxe kaart "Tijd voor nieuwe schoenen": hoeveel km erop zit, en meteen een nieuw paar bekijken
/// bij de hardloopwinkel, afschrijven of later herinneren.
///
/// [respectSnooze]: op Vandaag niet tonen als je "Later" koos; in Mijn schoenen altijd.
class ShoeReplaceCard extends ConsumerStatefulWidget {
  const ShoeReplaceCard({super.key, this.respectSnooze = true});
  final bool respectSnooze;

  @override
  ConsumerState<ShoeReplaceCard> createState() => _ShoeReplaceCardState();
}

class _ShoeReplaceCardState extends ConsumerState<ShoeReplaceCard> {
  static const _snoozeDays = 30;
  Set<String> _snoozed = const {};

  @override
  void initState() {
    super.initState();
    _loadSnoozes();
  }

  static String _key(String id) => 'shoe_snooze_$id';

  Future<void> _loadSnoozes() async {
    try {
      final p = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final out = <String>{};
      for (final k in p.getKeys().where((k) => k.startsWith('shoe_snooze_'))) {
        final until = DateTime.tryParse(p.getString(k) ?? '');
        if (until != null && until.isAfter(now)) out.add(k.substring('shoe_snooze_'.length));
      }
      if (mounted) setState(() => _snoozed = out);
    } catch (_) {}
  }

  Future<void> _later(Shoe s) async {
    HapticFeedback.selectionClick();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key(s.id!), DateTime.now().add(const Duration(days: _snoozeDays)).toIso8601String());
    } catch (_) {}
    if (!mounted) return;
    setState(() => _snoozed = {..._snoozed, s.id!});
    showMessage(context, 'We herinneren je over een maand.');
  }

  Future<void> _retire(Shoe s) async {
    final ok = await confirmDialog(
      context,
      title: '${s.name} afschrijven?',
      message: 'Hij telt dan niet meer mee voor nieuwe runs. Je kunt hem later weer in gebruik nemen.',
      confirmLabel: 'Afschrijven',
      destructive: false,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(repositoryProvider).retireShoe(s.id!, true);
      ref.invalidate(shoesProvider);
      if (mounted) showMessage(context, '${s.name} afgeschreven. Voeg je nieuwe paar toe in Mijn schoenen.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _shop(ShoeShop shop, Shoe s) async {
    HapticFeedback.lightImpact();
    final ok = await launchUrl(shop.urlFor(s.name), mode: LaunchMode.externalApplication).catchError((Object _) => false);
    if (!ok && mounted) showMessage(context, 'De winkel kon niet worden geopend.', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final shoes = ref.watch(shoesProvider).value ?? const <Shoe>[];
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final pick = shoeToReplace(
      [for (final s in shoes) if (!widget.respectSnooze || !_snoozed.contains(s.id)) s],
      runs,
    );
    if (pick == null) return const SizedBox.shrink();
    final shop = ref.watch(shoeShopProvider).value ?? ShoeShop.fallback;
    final s = pick.shoe;
    final pct = (pick.km / s.limitKm * 100).round();

    return Semantics(
      container: true,
      label: 'Tijd voor nieuwe schoenen. ${s.name} heeft ${pick.km.round()} van ${s.limitKm} kilometer.',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _gold.withValues(alpha: 0.55)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF241B0C), Color(0xFF15120D), RwColors.surface],
          ),
          boxShadow: [BoxShadow(color: _gold.withValues(alpha: 0.12), blurRadius: 24, spreadRadius: -6)],
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _WearRing(fraction: pick.km / s.limitKm, label: '$pct%'),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TIJD VOOR NIEUWE SCHOENEN',
                          style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
                      const SizedBox(height: 4),
                      Text(s.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: RwFonts.display, fontSize: 22, fontWeight: FontWeight.w800, height: 1.1)),
                      const SizedBox(height: 2),
                      Text('${pick.km.round()} van ${s.limitKm} km',
                          style: const TextStyle(color: RwColors.muted, fontFeatures: rwTnum)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              shop.isFallback
                  ? 'Na zo\'n ${s.limitKm} km nemen demping en grip merkbaar af. Een nieuw paar loopt prettiger en helpt blessures voorkomen.'
                  : 'Na zo\'n ${s.limitKm} km nemen demping en grip merkbaar af. Laat je bij ${shop.name} adviseren: '
                      'neem je oude paar mee, dan zien ze hoe je loopt.',
              style: const TextStyle(color: RwColors.muted, height: 1.45),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: const Color(0xFF1C1405),
                minimumSize: const Size.fromHeight(50),
                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              onPressed: () => _shop(shop, s),
              icon: const Icon(Icons.storefront_outlined),
              label: Text(shop.isFallback ? 'Zoek een nieuw paar' : 'Bekijk bij ${shop.name}'),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(onPressed: () => _retire(s), child: const Text('Afschrijven')),
                if (widget.respectSnooze)
                  TextButton(
                    onPressed: () => _later(s),
                    child: const Text('Later', style: TextStyle(color: RwColors.subtle)),
                  ),
              ],
            ),
            if (shop.isPartner)
              const Text(
                'Partnerlink: RunWise krijgt een kleine vergoeding als je iets koopt. Jij betaalt niets extra.',
                textAlign: TextAlign.center,
                style: TextStyle(color: RwColors.subtle, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

/// Gouden ring die vol loopt naarmate de schoen zijn grens nadert.
class _WearRing extends StatelessWidget {
  const _WearRing({required this.fraction, required this.label});
  final double fraction;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 74,
        height: 74,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, f, child) => CustomPaint(painter: _RingPainter(f), child: child),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.directions_run, size: 18, color: _gold),
              FittedBox(
                child: Text(label,
                    style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ]),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.f);
  final double f;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = RwColors.bar);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * f,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(colors: [_goldDeep, _gold, Color(0xFFF3DC95)], startAngle: 0, endAngle: math.pi * 2)
            .createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.f != f;
}

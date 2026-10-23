import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/billing_service.dart';
import '../../domain/geo.dart';
import '../../shared/widgets.dart';
import '../routes/poster_design.dart';

const luxeGold = Color(0xFFD9B45A);

/// Een grillig rondje als voorbeeld in het verkoopvenster.
final String _samplePolyline = encodePolyline([
  for (var i = 0; i <= 48; i++)
    () {
      final t = i / 48 * 2 * math.pi;
      final r = 1 + 0.18 * math.cos(3 * t) + 0.08 * math.sin(5 * t);
      return LatLng(52.15 + 0.012 * r * math.sin(t), 5.59 + 0.019 * r * math.cos(t));
    }(),
]);
const _ink = Color(0xFF1C1405);
const _cacheKey = 'luxe_owned';

/// Mag deze gebruiker de Luxe-ontwerpen gebruiken? Premium: altijd. Anders: gekocht via RevenueCat.
/// De uitkomst wordt bewaard, zodat het ook zonder internet klopt.
final luxeAccessProvider = FutureProvider<bool>((ref) async {
  final profile = await ref.watch(profileProvider.future).catchError((Object _) => null);
  if (profile?.isPremium ?? false) return true;
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {}
  final cached = prefs?.getBool(_cacheKey) ?? false;
  final user = ref.watch(currentUserProvider);
  final billing = ref.read(billingServiceProvider);
  if (user == null || !billing.isAvailable) return cached;
  try {
    final owned = await billing.hasLuxeDesigns(user.id);
    await prefs?.setBool(_cacheKey, owned);
    return owned;
  } catch (_) {
    return cached;
  }
});

/// Klein gouden "Luxe"-label voor op knoppen en stijlkeuzes.
class LuxeBadge extends StatelessWidget {
  const LuxeBadge({super.key, this.locked = true});
  final bool locked;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: luxeGold, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(locked ? Icons.lock : Icons.auto_awesome, size: 10, color: _ink),
          const SizedBox(width: 3),
          const Text('LUXE', style: TextStyle(color: _ink, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        ]),
      );
}

/// Verkoopvenster voor de Luxe-ontwerpen. Geeft true als ze nu te gebruiken zijn.
Future<bool> showLuxeSheet(BuildContext context, WidgetRef ref) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF0D0B08),
    builder: (_) => const _LuxeSheet(),
  );
  return ok ?? false;
}

class _LuxeSheet extends ConsumerStatefulWidget {
  const _LuxeSheet();

  @override
  ConsumerState<_LuxeSheet> createState() => _LuxeSheetState();
}

class _LuxeSheetState extends ConsumerState<_LuxeSheet> {
  String? _price;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPrice();
  }

  Future<void> _loadPrice() async {
    final user = ref.read(currentUserProvider);
    final billing = ref.read(billingServiceProvider);
    if (user == null || !billing.isAvailable) return;
    try {
      final p = await billing.luxePrice(user.id);
      if (mounted) setState(() => _price = p);
    } catch (_) {}
  }

  Future<void> _buy() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final owned = await ref.read(billingServiceProvider).buyLuxeDesigns(user.id);
      ref.invalidate(luxeAccessProvider);
      if (!mounted) return;
      if (owned) {
        HapticFeedback.heavyImpact();
        showMessage(context, 'Luxe-ontwerpen ontgrendeld. Veel plezier!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final billing = ref.read(billingServiceProvider);
      await billing.restore(user.id);
      final owned = await billing.hasLuxeDesigns(user.id);
      ref.invalidate(luxeAccessProvider);
      if (!mounted) return;
      showMessage(context, owned ? 'Je Luxe-ontwerpen zijn terug.' : 'Geen eerdere aankoop gevonden.');
      if (owned) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.read(billingServiceProvider).isAvailable;
    final sample = PosterData(title: 'Rondje', polyline: _samplePolyline, distanceMeters: 8200);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFF3DC95), luxeGold, Color(0xFF9C7A2E)]).createShader(r),
              child: const Text('Luxe-ontwerpen',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: RwFonts.display, fontSize: 30, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 6),
            const Text('Voor je routeposters en deelkaarten. Eenmalig, voor altijd van jou.',
                textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted, height: 1.4)),
            const SizedBox(height: 18),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: PosterStyle.values.where((s) => s.isLuxe).length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final st = PosterStyle.values.where((s) => s.isLuxe).elementAt(i);
                  return Column(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(width: 96, height: 120, child: RoutePosterArt(data: sample, style: st)),
                    ),
                    const SizedBox(height: 6),
                    Text(st.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ]);
                },
              ),
            ),
            const SizedBox(height: 16),
            for (final (icon, text) in const [
              (Icons.image_outlined, 'Vier posterstijlen: Goud, Marmer, Oceaan en Blauwdruk'),
              (Icons.ios_share, 'Een gouden deelkaart voor je runs'),
              (Icons.print_outlined, 'Ook voor posters die je laat drukken'),
              (Icons.workspace_premium_outlined, 'Al inbegrepen als je Premium hebt'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Icon(icon, color: luxeGold, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
                ]),
              ),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: luxeGold,
                foregroundColor: _ink,
                minimumSize: const Size.fromHeight(54),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              onPressed: _busy || !available ? null : _buy,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _ink))
                  : Text(!available
                      ? 'Binnenkort te koop'
                      : _price == null
                          ? 'Ontgrendelen'
                          : 'Ontgrendel voor $_price'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      final router = GoRouter.of(context);
                      Navigator.pop(context, false);
                      router.push('/premium');
                    },
              child: const Text('Of neem Premium: alles inbegrepen', style: TextStyle(color: luxeGold)),
            ),
            if (available)
              TextButton(
                onPressed: _busy ? null : _restore,
                child: const Text('Aankoop herstellen', style: TextStyle(color: RwColors.subtle)),
              ),
          ],
        ),
      ),
    );
  }
}

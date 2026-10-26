import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/poster_order_service.dart';
import '../../domain/shoe_shop.dart';
import '../../domain/shoes.dart';
import '../../shared/widgets.dart';
import '../luxe/luxe.dart';
import '../profile/shoe_replace_card.dart' show shoeShopProvider;
import '../routes/poster_design.dart';
import '../routes/route_poster_screen.dart';

/// De Kadans-shop: routeposters, Luxe-ontwerpen, Premium en hardloopschoenen op één plek.
/// Altijd donker en goud, ook als de app licht staat (net als Premium en Luxe).
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  static const _bg = Color(0xFF0D0B08);
  static const _gold = Color(0xFFD9BF92);
  static const _goldLight = Color(0xFFF0DDB6);
  static const _goldDeep = Color(0xFFB8955F);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = rwZandAvond;
    final routes = ref.watch(routesProvider).value ?? const <RunRoute>[];
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final products = ref.watch(posterProductsProvider).value ?? const <PosterProduct>[];
    final luxe = ref.watch(luxeAccessProvider).value ?? false;
    final premium = ref.watch(profileProvider).value?.isPremium ?? false;
    final shop = ref.watch(shoeShopProvider).value ?? ShoeShop.fallback;
    final shoes = ref.watch(shoesProvider).value ?? const <Shoe>[];

    // Favorieten eerst, dan de routes die je het vaakst liep.
    int times(RunRoute r) => runs.where((a) => a.routeId != null && a.routeId == r.id).length;
    final sorted = [...routes.where((r) => r.polyline.isNotEmpty)]
      ..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return times(b).compareTo(times(a));
      });
    final shown = sorted.take(8).toList();
    final from = products.isEmpty ? null : (products.map((p) => p.priceCents).reduce((a, b) => a < b ? a : b));
    final fromLabel = from == null ? null : 'vanaf € ${(from / 100).toStringAsFixed(2).replaceAll('.', ',')}';

    final body = TextStyle(color: pal.muted, height: 1.45, fontSize: 14);
    return Theme(
      data: buildTheme().copyWith(
        scaffoldBackgroundColor: _bg,
        appBarTheme: const AppBarTheme(backgroundColor: _bg, foregroundColor: _goldLight, elevation: 0, scrolledUnderElevation: 0),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: pal.text),
        child: Scaffold(
          appBar: AppBar(title: const Text('Shop'), foregroundColor: _goldLight),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              Text('KADANS SHOP', style: TextStyle(color: _gold, letterSpacing: 4, fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 6),
              Text('Jouw rondjes, mooi gemaakt', style: RwText.title.copyWith(color: pal.text)),
              const SizedBox(height: 6),
              Text('Laat een route drukken als poster, ontgrendel de Luxe-ontwerpen of vind nieuwe schoenen.', style: body),
              const SizedBox(height: 22),

              // Routeposters
              _Header(icon: Icons.image_outlined, title: 'Routeposters', trailing: fromLabel),
              const SizedBox(height: 10),
              if (shown.isEmpty)
                _Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Nog geen routes', style: TextStyle(color: pal.text, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Teken een rondje of laat er een maken; daarna kun je het hier als poster laten drukken.', style: body),
                    const SizedBox(height: 10),
                    _GoldButton(label: 'Naar routes', icon: Icons.route_outlined, onPressed: () => context.go('/routes')),
                  ]),
                )
              else
                SizedBox(
                  height: 236,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final r = shown[i];
                      final mine = runs.where((a) => a.routeId != null && a.routeId == r.id).toList();
                      final fastest = mine.isEmpty ? null : mine.map((a) => a.movingTimeSeconds).reduce((a, b) => a < b ? a : b);
                      return Semantics(
                        button: true,
                        label: 'Poster van ${r.name}',
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            openRoutePoster(context, r, fastestSeconds: fastest, timesRun: mine.length);
                          },
                          child: SizedBox(
                            width: 150,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: AspectRatio(
                                  aspectRatio: 3 / 4,
                                  child: IgnorePointer(
                                    child: RoutePosterArt(
                                      style: i.isEven ? PosterStyle.goud : PosterStyle.marmer,
                                      data: PosterData(
                                        title: r.name,
                                        polyline: r.polyline,
                                        distanceMeters: r.distanceMeters,
                                        elevationGainMeters: r.elevationGainMeters,
                                        fastestSeconds: fastest,
                                        timesRun: mine.length,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text('Tik op een route, kies een stijl en bestel. Gedrukt op mat papier en thuisbezorgd.',
                      style: body.copyWith(fontSize: 13)),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: _gold),
                  onPressed: () => context.push('/posters'),
                  icon: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: const Text('Mijn bestellingen'),
                ),
              ]),
              const SizedBox(height: 22),

              // Luxe-ontwerpen
              _Header(icon: Icons.auto_awesome_outlined, title: 'Luxe-ontwerpen', trailing: luxe ? 'Ontgrendeld' : null),
              const SizedBox(height: 10),
              _Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('4 posterstijlen (Goud, Marmer, Oceaan, Blauwdruk) en een gouden deelkaart. Eén keer kopen, voor altijd van jou. Bij Premium inbegrepen.',
                      style: body),
                  const SizedBox(height: 12),
                  _GoldButton(
                    label: luxe ? 'Bekijk je ontwerpen' : 'Bekijken en ontgrendelen',
                    icon: luxe ? Icons.check_circle_outline : Icons.lock_open_outlined,
                    onPressed: () => luxe && shown.isNotEmpty
                        ? openRoutePoster(context, shown.first)
                        : showLuxeSheet(context, ref),
                  ),
                ]),
              ),
              const SizedBox(height: 22),

              // Premium
              _Header(icon: Icons.workspace_premium_outlined, title: 'Kadans Premium', trailing: premium ? 'Actief' : null),
              const SizedBox(height: 10),
              _Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Je eigen AI-coach, een schema op maat, wedstrijdplan en een analyse na elke run. Luxe-ontwerpen zitten erbij.',
                      style: body),
                  const SizedBox(height: 4),
                  Text('1 maand gratis · daarna € 5 per maand of € 40 per jaar', style: body.copyWith(color: _goldLight, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  _GoldButton(
                    label: premium ? 'Je lidmaatschap' : 'Probeer 1 maand gratis',
                    icon: Icons.arrow_forward,
                    onPressed: () => context.push('/premium'),
                  ),
                  // Actiecodes (bijv. van een hardloper die je volgt) wissel je in bij Google Play.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: _gold),
                      onPressed: () => _redeem(context),
                      icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                      label: const Text('Heb je een code? Inwisselen'),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 22),

              // Schoenen
              _Header(icon: Icons.directions_run, title: 'Hardloopschoenen'),
              const SizedBox(height: 10),
              _Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    shop.isFallback
                        ? 'Zoek een nieuw paar op het web. Binnenkort met advies van een hardloopspeciaalzaak.'
                        : 'Nieuwe schoenen bij ${shop.name}${shop.isPartner ? ' (partnerlink: Kadans krijgt een klein deel, jij betaalt niets extra)' : ''}.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  _GoldButton(
                    label: () {
                      final d = defaultShoe(shoes);
                      return d == null ? 'Hardloopschoenen bekijken' : 'Nieuwe ${d.name}';
                    }(),
                    icon: Icons.open_in_new,
                    outlined: true,
                    onPressed: () async {
                      final d = defaultShoe(shoes);
                      final ok = await launchUrl(shop.urlFor(d?.name ?? 'hardloopschoenen'), mode: LaunchMode.externalApplication)
                          .catchError((Object _) => false);
                      if (!ok && context.mounted) showMessage(context, 'De winkel kon niet worden geopend.', error: true);
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 22),
              Text(
                'Posters betaal je via Stripe (iDEAL, bankpas of creditcard). Premium en Luxe lopen via Google Play.',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.subtle, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Actiecode inwisselen: Google Play opent met de code ingevuld; daarna staat het abonnement of de aankoop klaar.
Future<void> _redeem(BuildContext context) async {
  final ctrl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Code inwisselen'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Actiecode', hintText: 'Bijv. KADANS-RUNNER'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Inwisselen')),
      ],
    ),
  );
  ctrl.dispose();
  if (code == null || code.isEmpty) return;
  final ok = await launchUrl(Uri.parse('https://play.google.com/redeem?code=${Uri.encodeQueryComponent(code)}'),
          mode: LaunchMode.externalApplication)
      .catchError((Object _) => false);
  if (!ok && context.mounted) showMessage(context, 'Google Play kon niet worden geopend.', error: true);
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, this.trailing});
  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20, color: ShopScreen._gold),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              style: TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 19, color: rwZandAvond.text)),
        ),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: ShopScreen._goldDeep),
            ),
            child: Text(trailing!, style: const TextStyle(color: ShopScreen._goldLight, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
      ]);
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: rwZandAvond.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ShopScreen._goldDeep.withValues(alpha: 0.45)),
        ),
        child: child,
      );
}

class _GoldButton extends StatelessWidget {
  const _GoldButton({required this.label, required this.icon, required this.onPressed, this.outlined = false});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18),
      const SizedBox(width: 8),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ]);
    if (outlined) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: ShopScreen._goldLight,
          side: const BorderSide(color: ShopScreen._goldDeep),
          minimumSize: const Size(0, 46),
        ),
        onPressed: onPressed,
        child: child,
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: ShopScreen._gold,
        foregroundColor: rwZandAvond.accentDark,
        minimumSize: const Size(0, 46),
      ),
      onPressed: onPressed,
      child: child,
    );
  }
}

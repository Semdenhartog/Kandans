import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase.dart';
import '../../core/format.dart';
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
import '../../core/i18n.dart';

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
    final routes = ref.watch(routesProvider).value ?? <RunRoute>[];
    final runs = ref.watch(activitiesProvider).value ?? <Activity>[];
    final products = ref.watch(posterProductsProvider).value ?? <PosterProduct>[];
    final luxe = ref.watch(luxeAccessProvider).value ?? false;
    final premium = ref.watch(profileProvider).value?.isPremium ?? false;
    final shop = ref.watch(shoeShopProvider).value ?? ShoeShop.fallback;
    final shoes = ref.watch(shoesProvider).value ?? <Shoe>[];

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
        appBarTheme: AppBarTheme(backgroundColor: _bg, foregroundColor: _goldLight, elevation: 0, scrolledUnderElevation: 0),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: pal.text),
        child: Scaffold(
          appBar: AppBar(title: Text(tr('Shop')), foregroundColor: _goldLight),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              Text(tr('KADANS SHOP'), style: TextStyle(color: _gold, letterSpacing: 4, fontWeight: FontWeight.w800, fontSize: 12)),
              SizedBox(height: 6),
              Text(tr('Jouw rondjes, mooi gemaakt'), style: RwText.title.copyWith(color: pal.text)),
              SizedBox(height: 6),
              Text(tr('Laat een route drukken als poster, ontgrendel de Luxe-ontwerpen of vind nieuwe schoenen.'), style: body),
              SizedBox(height: 22),

              // Routeposters
              _Header(icon: Icons.image_outlined, title: tr('Routeposters'), trailing: fromLabel),
              SizedBox(height: 10),
              if (shown.isEmpty)
                _Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Nog geen routes'), style: TextStyle(color: pal.text, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text(tr('Teken een rondje of laat er een maken; daarna kun je het hier als poster laten drukken.'), style: body),
                    SizedBox(height: 10),
                    _GoldButton(label: tr('Naar routes'), icon: Icons.route_outlined, onPressed: () => context.go('/routes')),
                  ]),
                )
              else
                SizedBox(
                  height: 262,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final r = shown[i];
                      final mine = runs.where((a) => a.routeId != null && a.routeId == r.id).toList();
                      final fastest = mine.isEmpty ? null : mine.map((a) => a.movingTimeSeconds).reduce((a, b) => a < b ? a : b);
                      const styles = [PosterStyle.goud, PosterStyle.marmer, PosterStyle.topo];
                      return Semantics(
                        button: true,
                        label: 'Poster van ${r.name}',
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            openRoutePoster(context, r, fastestSeconds: fastest, timesRun: mine.length);
                          },
                          child: SizedBox(
                            width: 168,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _FramedPoster(
                                child: RoutePosterArt(
                                  style: styles[i % styles.length],
                                  data: PosterData(
                                    title: r.name,
                                    polyline: r.polyline,
                                    distanceMeters: r.distanceMeters,
                                    elevationGainMeters: r.elevationGainMeters,
                                    fastestSeconds: fastest,
                                    timesRun: mine.length,
                                    elevation: r.elevationProfile,
                                    startLat: r.startLatitude,
                                    startLon: r.startLongitude,
                                  ),
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
                              Text(
                                [
                                  Fmt.km(r.distanceMeters, decimals: 1),
                                  if (r.elevationGainMeters != null) '${r.elevationGainMeters!.round()} hm',
                                ].join(' · '),
                                maxLines: 1,
                                style: TextStyle(color: pal.muted, fontSize: 12),
                              ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _Feature(icon: Icons.straighten, text: tr('30 × 40 of 50 × 70 cm')),
                _Feature(icon: Icons.texture, text: tr('Mat papier, 200 g/m²')),
                _Feature(icon: Icons.terrain_outlined, text: tr('Hoogteprofiel en kilometers')),
                _Feature(icon: Icons.edit_outlined, text: tr('Eigen titel en tekst')),
              ]),
              SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text(tr('Tik op een route, kies een stijl en bestel. Gedrukt op mat papier en thuisbezorgd.'),
                      style: body.copyWith(fontSize: 13)),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: _gold),
                  onPressed: () => context.push('/posters'),
                  icon: Icon(Icons.local_shipping_outlined, size: 18),
                  label: Text(tr('Mijn bestellingen')),
                ),
              ]),
              SizedBox(height: 22),

              // Luxe-ontwerpen
              _Header(icon: Icons.auto_awesome_outlined, title: tr('Luxe-ontwerpen'), trailing: luxe ? 'Ontgrendeld' : null),
              SizedBox(height: 10),
              _Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('5 posterstijlen (Goud, Marmer, Topo, Oceaan, Blauwdruk) en een gouden deelkaart. Eén keer kopen, voor altijd van jou. Bij Premium inbegrepen.'),
                      style: body),
                  SizedBox(height: 12),
                  _GoldButton(
                    label: luxe ? tr('Bekijk je ontwerpen') : tr('Bekijken en ontgrendelen'),
                    icon: luxe ? Icons.check_circle_outline : Icons.lock_open_outlined,
                    onPressed: () => luxe && shown.isNotEmpty
                        ? openRoutePoster(context, shown.first)
                        : showLuxeSheet(context, ref),
                  ),
                ]),
              ),
              SizedBox(height: 22),

              // Premium
              _Header(icon: Icons.workspace_premium_outlined, title: tr('Kadans Premium'), trailing: premium ? 'Actief' : null),
              SizedBox(height: 10),
              _Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Je eigen AI-coach, een schema op maat, wedstrijdplan en een analyse na elke run. Luxe-ontwerpen zitten erbij.'),
                      style: body),
                  SizedBox(height: 4),
                  Text(tr('1 maand gratis · daarna € 5 per maand of € 40 per jaar'), style: body.copyWith(color: _goldLight, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text(tr('Wat gratis is, blijft gratis. Je runs exporteren kan altijd.'), style: body.copyWith(fontSize: 12.5)),
                  SizedBox(height: 12),
                  _GoldButton(
                    label: premium ? tr('Je lidmaatschap') : tr('Probeer 1 maand gratis'),
                    icon: Icons.arrow_forward,
                    onPressed: () => context.push('/premium'),
                  ),
                  // Actiecodes (bijv. van een hardloper die je volgt) wissel je in bij Google Play.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: _gold),
                      onPressed: () => _redeem(context, ref),
                      icon: Icon(Icons.confirmation_number_outlined, size: 18),
                      label: Text(tr('Heb je een code? Inwisselen')),
                    ),
                  ),
                ]),
              ),
              SizedBox(height: 22),

              // Schoenen
              _Header(icon: Icons.directions_run, title: tr('Hardloopschoenen')),
              SizedBox(height: 10),
              _Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    shop.isFallback
                        ? tr('Zoek een nieuw paar op het web. Binnenkort met advies van een hardloopspeciaalzaak.')
                        : 'Nieuwe schoenen bij ${shop.name}${shop.isPartner ? ' (partnerlink: Kadans krijgt een klein deel, jij betaalt niets extra)' : ''}.',
                    style: body,
                  ),
                  SizedBox(height: 12),
                  _GoldButton(
                    label: () {
                      final d = defaultShoe(shoes);
                      return d == null ? tr('Hardloopschoenen bekijken') : 'Nieuwe ${d.name}';
                    }(),
                    icon: Icons.open_in_new,
                    outlined: true,
                    onPressed: () async {
                      final d = defaultShoe(shoes);
                      final ok = await launchUrl(shop.urlFor(d?.name ?? 'hardloopschoenen'), mode: LaunchMode.externalApplication)
                          .catchError((Object _) => false);
                      if (!ok && context.mounted) showMessage(context, tr('De winkel kon niet worden geopend.'), error: true);
                    },
                  ),
                ]),
              ),
              SizedBox(height: 22),
              Text(tr('Posters betaal je via Stripe (iDEAL, bankpas of creditcard). Premium en Luxe lopen via Google Play.'),
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
Future<void> _redeem(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Code inwisselen')),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(labelText: tr('Actiecode of voucher'), hintText: tr('Bijv. LOPER30')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuleren'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('Inwisselen'))),
      ],
    ),
  );
  ctrl.dispose();
  if (code == null || code.isEmpty || !context.mounted) return;
  // Eerst onze eigen codes (gratis acties); onbekend? Dan is het misschien een Google Play-code.
  Map<String, dynamic>? r;
  try {
    r = (await ref.read(supabaseProvider).rpc('redeem_promo', params: {'code': code}) as Map).cast<String, dynamic>();
  } catch (_) {
    r = null;
  }
  if (!context.mounted) return;
  if (r != null && r['ok'] == true) {
    HapticFeedback.heavyImpact();
    ref.invalidate(profileProvider);
    ref.invalidate(luxeAccessProvider);
    final what = switch (r['grants']) { 'premium' => 'Premium', 'luxe' => 'de Luxe-ontwerpen', _ => 'Premium en de Luxe-ontwerpen' };
    final until = r['until'] == null ? 'voor altijd' : 'tot ${Fmt.date(DateTime.parse(r['until'] as String).toLocal())}';
    showMessage(context, 'Gelukt! Je hebt nu $what, $until.');
    return;
  }
  if (r != null && r['unknown'] != true) {
    showMessage(context, '${r['message'] ?? tr('Inwisselen lukte niet.')}', error: true);
    return;
  }
  final play = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Google Play-code?')),
      content: Text(tr('Deze code kennen we niet. Is het een code van Google Play? Dan wissel je hem daar in.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Nee'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Open Google Play'))),
      ],
    ),
  );
  if (play != true || !context.mounted) return;
  final ok = await launchUrl(Uri.parse('https://play.google.com/redeem?code=${Uri.encodeQueryComponent(code)}'),
          mode: LaunchMode.externalApplication)
      .catchError((Object _) => false);
  if (!ok && context.mounted) showMessage(context, tr('Google Play kon niet worden geopend.'), error: true);
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, this.trailing});
  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20, color: ShopScreen._gold),
        SizedBox(width: 8),
        Expanded(
          child: Text(title,
              style: TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 19, color: rwZandAvond.text)),
        ),
        if (trailing != null)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: ShopScreen._goldDeep),
            ),
            child: Text(trailing!, style: TextStyle(color: ShopScreen._goldLight, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
      ]);
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(16),
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
      SizedBox(width: 8),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ]);
    if (outlined) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: ShopScreen._goldLight,
          side: BorderSide(color: ShopScreen._goldDeep),
          minimumSize: Size(0, 46),
        ),
        onPressed: onPressed,
        child: child,
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: ShopScreen._gold,
        foregroundColor: rwZandAvond.accentDark,
        minimumSize: Size(0, 46),
      ),
      onPressed: onPressed,
      child: child,
    );
  }
}

/// Een poster in een dunne zwarte lijst met een wit passe-partout, tegen een warme muur.
class _FramedPoster extends StatelessWidget {
  const _FramedPoster({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A241C), Color(0xFF1A160F)],
          ),
        ),
        child: Center(
          child: FractionallySizedBox(
            heightFactor: 0.86,
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Color(0xFF0B0A08),
                  boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 14, offset: Offset(0, 8))],
                ),
                child: Container(
                  color: const Color(0xFFF7F3EC),
                  padding: const EdgeInsets.all(8),
                  child: IgnorePointer(child: ClipRect(child: child)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0x55D9BF92)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: const Color(0xFFD9BF92)),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: const TextStyle(color: Color(0xFFE9DFCD), fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/services/poster_order_service.dart';
import '../../shared/widgets.dart';
import '../luxe/luxe.dart' show luxeGold;
import 'poster_design.dart';
import 'poster_orders_screen.dart';

/// Opent het bestellen van een gedrukte poster.
void openPosterOrder(BuildContext context, {required PosterData data, required PosterStyle style}) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PosterOrderScreen(data: data, style: style)));
}

const _ink = Color(0xFF1C1405);
const _addressKey = 'poster_shipping_address';

/// Kies formaat, vul je adres in en betaal: de poster wordt gedrukt en thuisbezorgd.
class PosterOrderScreen extends ConsumerStatefulWidget {
  const PosterOrderScreen({super.key, required this.data, required this.style});
  final PosterData data;
  final PosterStyle style;

  @override
  ConsumerState<PosterOrderScreen> createState() => _PosterOrderScreenState();
}

class _PosterOrderScreenState extends ConsumerState<PosterOrderScreen> {
  final _form = GlobalKey<FormState>();
  final _posterKey = GlobalKey();
  final _name = TextEditingController();
  final _street = TextEditingController();
  final _house = TextEditingController();
  final _postcode = TextEditingController();
  final _city = TextEditingController();
  final _email = TextEditingController();
  String _country = 'NL';
  PosterProduct? _product;
  String? _step; // tekst tijdens het bestellen

  @override
  void initState() {
    super.initState();
    _email.text = ref.read(currentUserProvider)?.email ?? '';
    _loadAddress();
  }

  @override
  void dispose() {
    for (final c in [_name, _street, _house, _postcode, _city, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAddress() async {
    try {
      final p = await SharedPreferences.getInstance();
      final a = ShippingAddress.fromJson(jsonDecode(p.getString(_addressKey) ?? 'null'));
      if (a == null || !mounted) return;
      setState(() {
        _name.text = a.name;
        _street.text = a.street;
        _house.text = a.houseNumber;
        _postcode.text = a.postcode;
        _city.text = a.city;
        _country = a.country;
        if (a.email.isNotEmpty) _email.text = a.email;
      });
    } catch (_) {}
  }

  ShippingAddress get _address => ShippingAddress(
        name: _name.text,
        street: _street.text,
        houseNumber: _house.text,
        postcode: _postcode.text,
        city: _city.text,
        country: _country,
        email: _email.text,
      );

  /// Maakt het drukbestand van de poster in het gekozen formaat.
  Future<Uint8List> _renderPrintFile(PosterProduct product) async {
    final boundary = _posterKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ratio = printWidthPx(product) / boundary.size.width;
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('Het drukbestand kon niet worden gemaakt.');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _pay() async {
    final product = _product;
    if (product == null) {
      showMessage(context, 'Kies eerst een formaat.', error: true);
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;
    HapticFeedback.mediumImpact();
    final service = ref.read(posterOrderServiceProvider);
    try {
      setState(() => _step = 'Drukbestand maken…');
      final png = await _renderPrintFile(product);
      setState(() => _step = 'Drukbestand klaarzetten…');
      final path = await service.uploadPrintFile(png);
      setState(() => _step = 'Betaalpagina openen…');
      final address = _address;
      final r = await service.order(
        product: product,
        title: widget.data.title,
        style: widget.style.name,
        filePath: path,
        address: address,
      );
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(_addressKey, jsonEncode(address.toJson()));
      } catch (_) {}
      final ok = await launchUrl(r.checkoutUrl, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!ok) throw Exception('De betaalpagina kon niet worden geopend.');
      // Na betalen komt de app terug via runwise://app/poster-besteld; tot die tijd staat de bestelling klaar.
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => PosterOrdersScreen(highlight: r.orderId)));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _step = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(posterProductsProvider);
    final list = products.value ?? const <PosterProduct>[];
    final product = _product ?? (list.isEmpty ? null : list.first);
    if (_product == null && product != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _product == null) setState(() => _product = product);
      });
    }
    final busy = _step != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Poster laten drukken')),
      body: products.hasError
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Posters bestellen is nog niet beschikbaar. Probeer het later opnieuw.',
                    textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted)),
              ),
            )
          : products.isLoading && list.isEmpty
              ? const LoadingView(cards: 2)
              : AbsorbPointer(
                  absorbing: busy,
                  child: Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      children: [
                        // Poster op ware verhouding, met een zachte schaduw alsof hij aan de muur hangt.
                        Center(
                          child: SizedBox(
                            width: 240,
                            child: AspectRatio(
                              aspectRatio: product?.aspect ?? 3 / 4,
                              child: DecoratedBox(
                                decoration: const BoxDecoration(boxShadow: [
                                  BoxShadow(color: Color(0x99000000), blurRadius: 28, offset: Offset(0, 14), spreadRadius: -6),
                                ]),
                                child: RepaintBoundary(
                                  key: _posterKey,
                                  child: RoutePosterArt(data: widget.data, style: widget.style),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _Heading('FORMAAT'),
                        for (final p in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _FormatTile(
                              product: p,
                              selected: p.id == product?.id,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _product = p);
                              },
                            ),
                          ),
                        const SizedBox(height: 14),
                        const _Heading('BEZORGEN BIJ'),
                        _field(_name, 'Voor- en achternaam',
                            autofill: AutofillHints.name,
                            validator: (v) => (v ?? '').trim().split(RegExp(r'\s+')).length < 2 ? 'Vul je voor- en achternaam in' : null),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 3, child: _field(_street, 'Straat', autofill: AutofillHints.streetAddressLine1)),
                          const SizedBox(width: 10),
                          Expanded(flex: 2, child: _field(_house, 'Huisnr.')),
                        ]),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            flex: 2,
                            child: _field(_postcode, 'Postcode',
                                autofill: AutofillHints.postalCode,
                                caps: TextCapitalization.characters,
                                validator: (v) {
                                  final t = (v ?? '').trim().toUpperCase();
                                  if (t.isEmpty) return 'Verplicht';
                                  if (_country == 'NL' && !RegExp(r'^[1-9][0-9]{3} ?[A-Z]{2}$').hasMatch(t)) return 'Bijv. 3771 AB';
                                  return null;
                                }),
                          ),
                          const SizedBox(width: 10),
                          Expanded(flex: 3, child: _field(_city, 'Plaats', autofill: AutofillHints.addressCity)),
                        ]),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DropdownButtonFormField<String>(
                            initialValue: _country,
                            decoration: const InputDecoration(labelText: 'Land'),
                            items: const [
                              DropdownMenuItem(value: 'NL', child: Text('Nederland')),
                              DropdownMenuItem(value: 'BE', child: Text('België')),
                              DropdownMenuItem(value: 'DE', child: Text('Duitsland')),
                              DropdownMenuItem(value: 'LU', child: Text('Luxemburg')),
                            ],
                            onChanged: (v) => setState(() => _country = v ?? 'NL'),
                          ),
                        ),
                        _field(_email, 'E-mail (voor de bevestiging)',
                            autofill: AutofillHints.email,
                            keyboard: TextInputType.emailAddress,
                            validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Dit e-mailadres klopt niet'),
                        const SizedBox(height: 8),
                        const _Note(Icons.local_shipping_outlined, 'Gedrukt in Europa en meestal binnen een week bij je thuis. Verzending is inbegrepen.'),
                        const _Note(Icons.lock_outline, 'Je betaalt veilig via Stripe, met iDEAL of je bankpas/creditcard.'),
                        const _Note(Icons.info_outline,
                            'De poster wordt speciaal voor jou gemaakt; daarom kun je hem niet retourneren. Is er iets mis met de druk, dan lossen we het op.'),
                        const SizedBox(height: 16),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: luxeGold,
                            foregroundColor: _ink,
                            minimumSize: const Size.fromHeight(56),
                            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          onPressed: busy || product == null ? null : _pay,
                          child: busy
                              ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _ink)),
                                  const SizedBox(width: 12),
                                  Text(_step!),
                                ])
                              : Text(product == null ? 'Kies een formaat' : 'Betalen · ${product.priceLabel}'),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? autofill,
    TextInputType? keyboard,
    TextCapitalization caps = TextCapitalization.words,
    String? Function(String?)? validator,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          decoration: InputDecoration(labelText: label),
          autofillHints: autofill == null ? null : [autofill],
          keyboardType: keyboard,
          textCapitalization: keyboard == TextInputType.emailAddress ? TextCapitalization.none : caps,
          validator: validator ?? (v) => (v ?? '').trim().isEmpty ? 'Verplicht' : null,
        ),
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(color: luxeGold, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
      );
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({required this.product, required this.selected, required this.onTap});
  final PosterProduct product;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF1E180C) : RwColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? luxeGold : RwColors.border, width: selected ? 1.5 : 1),
            ),
            child: Row(children: [
              // Kleine maatschets: verhouding van het formaat.
              SizedBox(
                width: 36,
                height: 44,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: product.aspect,
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: Border.all(color: selected ? luxeGold : RwColors.subtle, width: 1.5)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(product.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (product.description != null)
                    Text(product.description!, style: const TextStyle(color: RwColors.subtle, fontSize: 12)),
                ]),
              ),
              Text(product.priceLabel,
                  style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: RwColors.subtle),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: RwColors.muted, fontSize: 13, height: 1.4))),
        ]),
      );
}

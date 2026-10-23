import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/services/poster_order_service.dart';
import '../../shared/widgets.dart';
import '../luxe/luxe.dart' show luxeGold;

/// Je posterbestellingen en hoe ver ze zijn. [highlight]: net besteld (die lichten we uit).
/// [justPaid]: terug van de betaalpagina; dan verversen we even tot de betaling verwerkt is.
class PosterOrdersScreen extends ConsumerStatefulWidget {
  const PosterOrdersScreen({super.key, this.highlight, this.justPaid = false, this.cancelled = false});
  final String? highlight;
  final bool justPaid;
  final bool cancelled;

  @override
  ConsumerState<PosterOrdersScreen> createState() => _PosterOrdersScreenState();
}

class _PosterOrdersScreenState extends ConsumerState<PosterOrdersScreen> {
  Timer? _poll;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    ref.invalidate(posterOrdersProvider);
    if (widget.highlight != null) {
      // Een minuut lang elke 5 seconden kijken of de betaling binnen is.
      _poll = Timer.periodic(const Duration(seconds: 5), (t) {
        _polls++;
        final o = ref.read(posterOrdersProvider).value?.where((x) => x.id == widget.highlight).firstOrNull;
        if (_polls > 12 || (o != null && o.status != PosterOrderStatus.nieuw && o.status != PosterOrderStatus.betaald)) {
          t.cancel();
          return;
        }
        ref.invalidate(posterOrdersProvider);
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(posterOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mijn posters')),
      body: orders.when(
        loading: () => const LoadingView(cards: 2),
        error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(posterOrdersProvider)),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(posterOrdersProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (widget.justPaid)
                const _Banner(Icons.celebration_outlined, 'Bedankt voor je bestelling! Je krijgt een bevestiging per e-mail.'),
              if (widget.cancelled)
                const _Banner(Icons.info_outline, 'Betaling afgebroken. Je kunt het opnieuw proberen vanuit je route.'),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: EmptyState(
                    icon: Icons.image_outlined,
                    title: 'Nog geen posters',
                    message: 'Open een route, kies "Deel als poster" en dan "Laten drukken".',
                  ),
                ),
              for (final o in list) ...[
                _OrderCard(order: o, highlight: o.id == widget.highlight),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E180C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: luxeGold.withValues(alpha: 0.6)),
        ),
        child: Row(children: [
          Icon(icon, color: luxeGold),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
        ]),
      );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.highlight});
  final PosterOrder order;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final s = order.status;
    final color = switch (s) {
      PosterOrderStatus.inProductie || PosterOrderStatus.verzonden => RwColors.good,
      PosterOrderStatus.mislukt => RwColors.danger,
      PosterOrderStatus.geannuleerd => RwColors.subtle,
      _ => luxeGold,
    };
    final steps = [PosterOrderStatus.betaald, PosterOrderStatus.inProductie, PosterOrderStatus.verzonden];
    final reached = switch (s) {
      PosterOrderStatus.betaald || PosterOrderStatus.concept => 1,
      PosterOrderStatus.inProductie => 2,
      PosterOrderStatus.verzonden => 3,
      _ => 0,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RwColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: highlight ? luxeGold : RwColors.border, width: highlight ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(order.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          Text('€ ${(order.priceCents / 100).toStringAsFixed(2).replaceAll('.', ',')}',
              style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 2),
        Text('${order.productId.replaceAll('x', ' × ')} cm · ${Fmt.date(order.createdAt)}',
            style: const TextStyle(color: RwColors.subtle, fontSize: 12)),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(s.label, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ]),
        if (reached > 0) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (var i = 0; i < steps.length; i++)
              Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < steps.length - 1 ? 4 : 0),
                  decoration: BoxDecoration(color: i < reached ? luxeGold : RwColors.bar, borderRadius: BorderRadius.circular(2)),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          const Row(children: [
            Expanded(child: Text('Betaald', style: TextStyle(color: RwColors.subtle, fontSize: 11))),
            Expanded(child: Text('Gedrukt', textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 11))),
            Expanded(child: Text('Onderweg', textAlign: TextAlign.right, style: TextStyle(color: RwColors.subtle, fontSize: 11))),
          ]),
        ],
      ]),
    );
  }
}

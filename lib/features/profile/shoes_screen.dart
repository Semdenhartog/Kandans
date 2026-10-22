import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/shoes.dart';
import '../../shared/widgets.dart';

/// Mijn schoenen: hoeveel km erop zit en wanneer ze aan vervanging toe zijn.
class ShoesScreen extends ConsumerWidget {
  const ShoesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref, {required bool firstShoe}) async {
    final shoe = await showModalBottomSheet<Shoe>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: RwColors.surface,
      builder: (_) => _ShoeSheet(firstShoe: firstShoe),
    );
    if (shoe == null) return;
    try {
      await ref.read(repositoryProvider).addShoe(shoe);
      ref.invalidate(shoesProvider);
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> Function() f) async {
    try {
      await f();
      ref.invalidate(shoesProvider);
      ref.invalidate(activitiesProvider);
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shoes = ref.watch(shoesProvider);
    final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mijn schoenen')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref, firstShoe: (shoes.value ?? const []).where((s) => !s.retired).isEmpty),
        icon: const Icon(Icons.add),
        label: const Text('Schoen toevoegen'),
      ),
      body: shoes.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(shoesProvider)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.directions_walk,
              title: 'Nog geen schoenen',
              message: 'Voeg je hardloopschoenen toe. RunWise telt de kilometers en geeft een seintje '
                  'als ze aan vervanging toe zijn (meestal na 600 tot 800 km).',
              actionLabel: 'Schoen toevoegen',
              onAction: () => _add(context, ref, firstShoe: true),
            );
          }
          final active = list.where((s) => !s.retired).toList();
          final retired = list.where((s) => s.retired).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              for (final s in active) ...[
                _ShoeCard(
                  shoe: s,
                  km: shoeKm(s, runs),
                  onDefault: s.isDefault ? null : () => _act(context, ref, () => repo.setDefaultShoe(s.id!)),
                  onRetire: () => _act(context, ref, () => repo.retireShoe(s.id!, true)),
                ),
                const SizedBox(height: 10),
              ],
              if (retired.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Text('AFGESCHREVEN', style: TextStyle(color: RwColors.subtle, fontWeight: FontWeight.w600)),
                ),
                for (final s in retired)
                  ListTile(
                    title: Text(s.name),
                    subtitle: Text('${shoeKm(s, runs).round()} km'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => v == 'back'
                          ? _act(context, ref, () => repo.retireShoe(s.id!, false))
                          : _act(context, ref, () => repo.deleteShoe(s.id!)),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'back', child: Text('Weer in gebruik')),
                        PopupMenuItem(value: 'delete', child: Text('Verwijderen')),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Runs zonder schoen tellen mee voor je standaardschoen. Bij een run kies je ook een andere schoen.',
                style: TextStyle(color: RwColors.subtle, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShoeCard extends StatelessWidget {
  const _ShoeCard({required this.shoe, required this.km, required this.onDefault, required this.onRetire});
  final Shoe shoe;
  final double km;
  final VoidCallback? onDefault;
  final VoidCallback onRetire;

  @override
  Widget build(BuildContext context) {
    final f = (km / shoe.limitKm).clamp(0.0, 1.0);
    final worn = km >= shoe.limitKm * 0.9;
    final color = worn ? RwColors.danger : (f > 0.7 ? RwColors.warning : RwColors.good);
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(shoe.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              if (shoe.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: RwColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('Standaard', style: TextStyle(color: RwColors.accent, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'default' ? onDefault?.call() : onRetire(),
                itemBuilder: (_) => [
                  if (onDefault != null) const PopupMenuItem(value: 'default', child: Text('Maak standaard')),
                  const PopupMenuItem(value: 'retire', child: Text('Afschrijven')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Levensduur als ring die bij openen volloopt, met wat er nog in de schoen zit.
          Row(children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: f),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => SizedBox(
                width: 84,
                height: 84,
                child: CustomPaint(
                  painter: _LifeRingPainter(v),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${((1 - v) * 100).round()}%',
                          style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                      const Text('over', style: TextStyle(color: RwColors.subtle, fontSize: 10)),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(
                    text: '${km.round()}',
                    style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: ' / ${shoe.limitKm} km', style: const TextStyle(color: RwColors.muted)),
                ])),
                const SizedBox(height: 2),
                Text(
                  worn ? 'Aan vervanging toe' : 'Nog ongeveer ${(shoe.limitKm - km).clamp(0, 99999).round()} km te gaan',
                  style: TextStyle(color: worn ? RwColors.danger : RwColors.muted, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ]),
          if (worn) ...[
            const SizedBox(height: 8),
            const Text(
              'Tijd voor nieuwe schoenen: de demping is na zoveel kilometers flink minder. Dat vergroot de kans op blessures.',
              style: TextStyle(color: RwColors.danger, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShoeSheet extends StatefulWidget {
  const _ShoeSheet({required this.firstShoe});
  final bool firstShoe;

  @override
  State<_ShoeSheet> createState() => _ShoeSheetState();
}

class _ShoeSheetState extends State<_ShoeSheet> {
  final _name = TextEditingController();
  final _start = TextEditingController(text: '0');
  double _limit = 700;
  late bool _default = widget.firstShoe;

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Schoen toevoegen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFamily: RwFonts.display, fontFeatures: rwTnum)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Naam', hintText: 'Bijv. Pegasus 41 blauw', counterText: ''),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _start,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Km die er al op zitten'),
          ),
          const SizedBox(height: 14),
          Text('Seintje na ${_limit.round()} km', style: const TextStyle(fontWeight: FontWeight.w600)),
          Slider(
            value: _limit,
            min: 300,
            max: 1200,
            divisions: 18,
            label: '${_limit.round()} km',
            onChanged: (v) => setState(() => _limit = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _default,
            onChanged: (v) => setState(() => _default = v),
            title: const Text('Standaardschoen'),
            subtitle: const Text('Nieuwe runs tellen vanzelf mee voor deze schoen'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              final name = _name.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(
                context,
                Shoe(
                  name: name,
                  startKm: (Fmt.parseDecimal(_start.text) ?? 0).clamp(0, 5000).toDouble(),
                  limitKm: _limit.round(),
                  isDefault: _default,
                ),
              );
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
  }
}


/// Levensduurring: groen → oranje → rood naarmate de schoen meer kilometers heeft.
class _LifeRingPainter extends CustomPainter {
  _LifeRingPainter(this.f);
  final double f;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 6;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = RwColors.bar);
    if (f <= 0.001) return;
    const start = -1.5707963;
    canvas.drawArc(rect, start, 6.2831853 * f, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        transform: GradientRotation(start),
        colors: [RwColors.good, RwColors.warning, RwColors.danger],
        stops: [0.0, 0.7, 0.95],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _LifeRingPainter old) => old.f != f;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/rw_components.dart';
import '../../shared/widgets.dart';

/// Coach-scherm (paywall) volgens het Figma-ontwerp.
/// De AI-coach en betalen via Google Play komen in een volgende versie.
class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  bool _yearly = true;

  void _startTrial() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bijna klaar'),
        content: const Text(
          'RunWise Coach is nog in ontwikkeling. Zodra hij beschikbaar is, kun je hier je gratis '
          'proefmaand starten via Google Play. We laten het je weten in de app.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Oké'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final runs = ref.watch(activitiesProvider).when(
          data: (a) => a,
          loading: () => const <Activity>[],
          error: (_, _) => const <Activity>[],
        );
    final name = profile.when(data: (p) => p?.displayName ?? '', loading: () => '', error: (_, _) => '');
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final thisWeek = runs.where((a) => !a.startedAt.toLocal().isBefore(monday)).length;

    final opener = thisWeek == 0
        ? 'Hoi${name.isEmpty ? '' : ' $name'}! Deze week heb je nog niet gelopen. Zullen we een schema maken voor een 10 km onder de 50 minuten?'
        : 'Hoi${name.isEmpty ? '' : ' $name'}! Je liep deze week $thisWeek keer. Zullen we toewerken naar een 10 km onder de 50 minuten?';

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const PageHeader(title: 'Coach', subtitle: 'Je persoonlijke hardloopcoach, 24/7'),
            const SizedBox(height: 16),
            RwPanel(
              child: Column(
                children: [
                  _Bubble(text: opener, fromCoach: true),
                  const SizedBox(height: 12),
                  const _Bubble(text: 'Ja! Hoe vaak moet ik daarvoor per week lopen?', fromCoach: false),
                  const SizedBox(height: 12),
                  const Opacity(
                    opacity: 0.3,
                    child: _Bubble(
                      text: 'Drie keer per week is ideaal: één intervaltraining, één tempoloop en één rustige '
                          'duurloop. Ik plan ze voor je in rond…',
                      fromCoach: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            RwPanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      IconBox(icon: Icons.lock_outline, size: 48, iconSize: 22, circle: true),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ontgrendel RunWise Coach',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: RwColors.tekst)),
                            SizedBox(height: 4),
                            Text('De eerste maand is gratis',
                                style: TextStyle(fontSize: 14, color: RwColors.tekstZacht)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const BenefitRow('Trainingsschema op maat, op basis van je eigen trainingen'),
                  const SizedBox(height: 12),
                  const BenefitRow('Advies per run: tempo, route en hoe je de wind slim gebruikt'),
                  const SizedBox(height: 12),
                  const BenefitRow('Stel al je vragen over hardlopen, blessures en voeding'),
                  const SizedBox(height: 12),
                  const BenefitRow('Schema past zich aan als je een training mist'),
                  const SizedBox(height: 16),
                  _PlanOption(
                    title: 'Jaar',
                    badge: 'Beste keuze',
                    price: '€40 per jaar',
                    note: '€3,33 per maand · bespaar 33%',
                    selected: _yearly,
                    onTap: () => setState(() => _yearly = true),
                  ),
                  const SizedBox(height: 8),
                  _PlanOption(
                    title: 'Maand',
                    price: '€5 per maand',
                    note: 'Maandelijks opzegbaar',
                    selected: !_yearly,
                    onTap: () => setState(() => _yearly = false),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: RwColors.oranje,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _startTrial,
                    child: const Text('Start 1 maand gratis'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Na je gratis maand betaal je ${_yearly ? '€40 per jaar' : '€5 per maand'}. '
                    'Je abonnement wordt automatisch verlengd en is altijd op te zeggen via Google Play.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, height: 16 / 12, color: RwColors.tekstZacht),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => showMessage(context, 'Geen eerdere aankopen gevonden.'),
                    child: const Text('Aankoop herstellen',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.fromCoach});
  final String text;
  final bool fromCoach;

  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(RwRadius.r16);
    const tail = Radius.circular(4);
    final bubble = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fromCoach ? RwColors.primairZacht : RwColors.primair,
        borderRadius: BorderRadius.only(
          topLeft: r,
          topRight: r,
          bottomLeft: fromCoach ? tail : r,
          bottomRight: fromCoach ? r : tail,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          height: 20 / 14,
          color: fromCoach ? RwColors.tekst : RwColors.opPrimair,
        ),
      ),
    );
    if (!fromCoach) {
      return Padding(padding: const EdgeInsets.only(left: 72), child: Align(alignment: Alignment.centerRight, child: bubble));
    }
    return Padding(
      padding: const EdgeInsets.only(right: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const IconBox(
            icon: Icons.auto_awesome_outlined,
            size: 28,
            iconSize: 14,
            background: RwColors.primair,
            color: RwColors.opPrimair,
            circle: true,
          ),
          const SizedBox(width: 8),
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.title,
    required this.price,
    required this.note,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String price;
  final String note;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? RwColors.primairZacht : RwColors.oppervlak,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RwRadius.r16),
        side: BorderSide(color: selected ? RwColors.primair : RwColors.rand, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(RwRadius.r16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: RwColors.tekst)),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Pill(badge!, small: true),
                  ],
                  const Spacer(),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? RwColors.primair : Colors.transparent,
                      border: selected ? null : Border.all(color: RwColors.rand, width: 2),
                    ),
                    child: selected ? const Icon(Icons.check, size: 14, color: RwColors.opPrimair) : null,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(price, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: RwColors.tekst)),
              const SizedBox(height: 4),
              Text(note, style: const TextStyle(fontSize: 13, color: RwColors.tekstZacht)),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../data/services/location_service.dart';
import '../../data/services/notification_service.dart';
import '../../domain/availability.dart';
import '../../domain/run_goal.dart';
import '../../shared/route_backdrop.dart';
import '../planner/availability_provider.dart';
import '../routes/watch_export.dart' show WatchBrand, WatchBrandInfo, saveWatchBrand;

const _doneKey = 'onboarding_done_v1';

Future<bool> onboardingDone() async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_doneKey) ?? false;
  } catch (_) {
    return true; // Bij twijfel niet steeds opnieuw tonen.
  }
}

Future<void> _markDone() async {
  try {
    await (await SharedPreferences.getInstance()).setBool(_doneKey, true);
  } catch (_) {}
}

/// Wat de gebruiker na de rondleiding wil doen.
enum OnboardingNext { today, connect, route, race }

/// Snelle keuzes voor "wanneer loop je meestal?" (sleutel uit [Availability.preset]).
const _whenChoices = [
  ('ochtend', 'Vroeg in de ochtend', Icons.wb_twilight),
  ('werk', 'Na het werk, weekend overdag', Icons.work_outline),
  ('avond', 'In de avond', Icons.nights_stay_outlined),
  ('altijd', 'Wisselend (bijv. diensten)', Icons.shuffle),
];

/// Kort overzicht van wat er in de app zit, voor de uitlegpagina.
const _features = [
  (Icons.wb_sunny_outlined, 'Vandaag', 'Je beste moment, met weer, wind, buien en wat je aantrekt.'),
  (Icons.route_outlined, 'Routes', 'Tekenen of laten maken, met ondergrond, verlichting en wind.'),
  (Icons.play_circle_outline, 'Opnemen', 'Lopen met stem, tempo-doel, live opdrachten en afslagen op je horloge.'),
  (Icons.flag_outlined, 'Uitdagingen en Samen', 'Doelen per maand, medailles en ranglijsten met vrienden.'),
  (Icons.event_outlined, 'Wedstrijden', 'Je wedstrijd met schema, tempo per km en aftellen.'),
  (Icons.auto_awesome_outlined, 'Coach', 'Vraag alles over je training; kent je eigen runs.'),
];

/// Toont de rondleiding als die nog niet is gezien. Geeft de gekozen vervolgstap terug.
Future<OnboardingNext?> showOnboardingIfNeeded(BuildContext context) async {
  if (await onboardingDone()) return null;
  if (!context.mounted) return null;
  final next = await Navigator.of(context).push<OnboardingNext>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const OnboardingScreen()),
  );
  await _markDone();
  return next ?? OnboardingNext.today;
}

/// Rondleiding bij de eerste keer openen: uitleg, een paar vragen die meteen je instellingen vullen,
/// en elke stap is over te slaan. Ook later terug te zien via Ik → Hulp.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.initialPage = 0});

  /// Voor schermafbeeldingen: op welke pagina beginnen.
  final int initialPage;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final _pages = PageController(initialPage: widget.initialPage);
  late int _page = widget.initialPage;
  RunGoal? _goal;
  String? _when;
  bool _reminder = false;
  bool _asking = false;
  String? _locationResult;
  WatchBrand? _brand;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() => _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);

  Future<void> _askLocation() async {
    setState(() => _asking = true);
    await markLocationExplained();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _locationResult = 'Locatie staat uit op je telefoon. Kadans gebruikt nu je thuisplaats of Barneveld.';
      } else {
        var p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
        _locationResult = p == LocationPermission.denied || p == LocationPermission.deniedForever
            ? 'Geen probleem. Kadans gebruikt dan het weer van Barneveld; je kunt dit later aanzetten.'
            : 'Top, het weer klopt nu voor jouw plek.';
      }
    } catch (_) {
      _locationResult = 'Dat lukte niet. Je kunt het later aanzetten in de instellingen van je telefoon.';
    }
    if (!mounted) return;
    setState(() => _asking = false);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) _next();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Page(
        icon: Icons.wb_sunny_outlined,
        title: 'Loop op het beste moment',
        text: 'Strava laat zien wat je gelopen hebt. Kadans zegt wanneer je het best kunt gaan: '
            'op het weer, de wind op jouw route en de buien van het komende uur. En welke kant je op moet en wat je aantrekt.',
        children: [
          FilledButton(onPressed: _next, child: const Text('Verder')),
        ],
      ),
      _Page(
        icon: Icons.apps_outlined,
        title: 'Alles op een rij',
        text: 'Dit zit er in Kadans. Je vindt het later terug onder de knoppen onderaan, en uitleg onder Ik → Hulp.',
        children: [
          for (final (icon, name, what) in _features)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 22, color: RwColors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '$name  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: what, style: TextStyle(color: RwColors.muted)),
                  ])),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _next, child: const Text('Verder')),
        ],
      ),
      _Page(
        icon: Icons.emoji_events_outlined,
        title: 'Waarvoor loop je?',
        text: 'Dan houdt de coach daar rekening mee. Kies je een wedstrijd, dan zet je hem aan het eind meteen in de app.',
        children: [
          for (final g in RunGoal.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Choice(
                label: g.label,
                selected: _goal == g,
                onTap: () async {
                  setState(() => _goal = g);
                  await saveRunGoal(g);
                  await Future<void>.delayed(const Duration(milliseconds: 300));
                  if (mounted) _next();
                },
              ),
            ),
          TextButton(onPressed: _next, child: const Text('Sla over')),
        ],
      ),
      _Page(
        icon: Icons.schedule,
        title: 'Wanneer loop je meestal?',
        text: 'Kadans zoekt je beste moment alleen binnen die tijden. Je past ze altijd aan in de weekplanner.',
        children: [
          for (final (key, label, icon) in _whenChoices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Choice(
                label: label,
                icon: icon,
                selected: _when == key,
                onTap: () async {
                  setState(() => _when = key);
                  await saveAvailability(ref, Availability.preset(key));
                },
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _reminder,
            title: const Text('Elke ochtend je beste moment als melding'),
            subtitle: Text('Eén melding per dag, geen reclame. Je telefoon vraagt zo om toestemming.',
                style: TextStyle(color: RwColors.muted)),
            onChanged: (on) async {
              final ok = await NotificationService.instance.setEnabled(on);
              if (mounted) setState(() => _reminder = on && ok);
            },
          ),
          const SizedBox(height: 4),
          FilledButton(onPressed: _next, child: Text(_when == null && !_reminder ? 'Sla over' : 'Verder')),
        ],
      ),
      _Page(
        icon: Icons.my_location,
        title: 'Het weer op jouw plek',
        text: 'Daarvoor vraagt Kadans je locatie, alleen terwijl je de app gebruikt. We bewaren hooguit een '
            'grove thuisplaats (op ongeveer 1 km afgerond) en delen je locatie met niemand, tenzij je zelf live delen aanzet.',
        children: [
          if (_locationResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_locationResult!, textAlign: TextAlign.center, style: TextStyle(color: RwColors.good)),
            ),
          FilledButton.icon(
            onPressed: _asking || _locationResult != null ? null : _askLocation,
            icon: _asking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.location_on_outlined),
            label: const Text('Locatie toestaan'),
          ),
          TextButton(
            onPressed: () async {
              await markLocationExplained();
              _next();
            },
            child: const Text('Later'),
          ),
        ],
      ),
      _Page(
        icon: Icons.watch_outlined,
        title: 'Welk horloge heb je?',
        text: 'Dan zet Kadans je route met één knop op je horloge, met een trilling bij elke afslag. '
            'Geen horloge? Dan zegt je telefoon de afslagen.',
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in WatchBrand.values)
                ChoiceChip(
                  label: Text(b == WatchBrand.wearos ? 'Wear OS (Galaxy, Pixel)' : b == WatchBrand.garminBasic ? 'Garmin zonder routes (Vivoactive 5)' : b.label),
                  selected: _brand == b,
                  onSelected: (_) async {
                    setState(() => _brand = b);
                    await saveWatchBrand(b);
                    await Future<void>.delayed(const Duration(milliseconds: 350));
                    if (mounted) _next();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _next, child: const Text('Later kiezen')),
        ],
      ),
      _Page(
        icon: Icons.sync,
        title: 'Werkt naast Strava',
        text: 'Koppel Strava voor je oude runs en routes, en je horloge (via Health Connect) voor nieuwe runs. '
            'Dan leert Kadans bij welk weer jij het snelst loopt. Strava blijft voor je kudos; Kadans plant je volgende run.',
        children: [
          if (_goal == RunGoal.race) ...[
            FilledButton(
              onPressed: () => Navigator.pop(context, OnboardingNext.race),
              child: const Text('Mijn wedstrijd toevoegen'),
            ),
            const SizedBox(height: 8),
          ],
          if (_goal == RunGoal.race)
            OutlinedButton(
              onPressed: () => Navigator.pop(context, OnboardingNext.connect),
              child: const Text('Strava of horloge koppelen'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(context, OnboardingNext.connect),
              child: const Text('Strava of horloge koppelen'),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, OnboardingNext.route),
            child: const Text('Eerst een rondje maken'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, OnboardingNext.today),
            child: const Text('Naar mijn beste moment van vandaag'),
          ),
        ],
      ),
    ];

    // Terugknop van Android: eerst een stap terug in de rondleiding, pas op de eerste stap sluiten.
    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _page > 0) {
          _pages.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
        }
      },
      child: Scaffold(
      body: Stack(children: [
        // Een route die zich met elke pagina verder intekent, met een lopende stip aan de kop.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pages,
              builder: (_, _) {
                final page = _pages.hasClients && _pages.position.haveDimensions ? (_pages.page ?? 0) : _page.toDouble();
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 1400),
                  curve: Curves.easeOutCubic,
                  builder: (_, intro, _) => CustomPaint(
                    painter: RouteBackdropPainter(progress: intro * (0.38 + page * 0.21).clamp(0.0, 1.0)),
                  ),
                );
              },
            ),
          ),
        ),
        SafeArea(
        child: Column(
          children: [
            Row(children: [
              // Terug naar de vorige stap (vegen kan ook).
              AnimatedOpacity(
                opacity: _page > 0 ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IconButton(
                  tooltip: 'Vorige',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _page > 0
                      ? () => _pages.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic)
                      : null,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await markLocationExplained();
                  if (context.mounted) Navigator.pop(context, OnboardingNext.today);
                },
                child: const Text('Overslaan'),
              ),
            ]),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    GestureDetector(
                      onTap: () => _pages.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic),
                      child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? RwColors.accent : RwColors.bar,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      ]),
    ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.icon, required this.title, required this.text, required this.children});
  final IconData icon;
  final String title;
  final String text;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        // Tekst bovenaan, knoppen onderaan binnen bereik van je duim; scrollt op kleine schermen.
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 12),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Center(
                    child: Container(
                      width: 168,
                      height: 168,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          RwColors.accent.withValues(alpha: 0.35),
                          RwColors.accentDeep.withValues(alpha: 0.08),
                          Colors.transparent,
                        ], stops: const [0, 0.7, 1]),
                      ),
                      child: Icon(icon, size: 76, color: RwColors.accent),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 32, fontWeight: FontWeight.w800, height: 1.1)),
                  const SizedBox(height: 16),
                  Text(text, textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted, fontSize: 16, height: 1.5)),
                  const Spacer(flex: 2),
                  const SizedBox(height: 24),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      );
}

/// Grote keuzeknop voor de vragen in de rondleiding.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? RwColors.accent.withValues(alpha: 0.16) : RwColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? RwColors.accent : RwColors.bar, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 20, color: RwColors.accent), const SizedBox(width: 12)],
              Expanded(child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              if (selected) Icon(Icons.check_circle, size: 20, color: RwColors.accent),
            ]),
          ),
        ),
      );
}

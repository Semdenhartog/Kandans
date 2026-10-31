import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../data/services/location_service.dart';
import '../../data/services/notification_service.dart';
import '../../domain/availability.dart';
import '../../domain/run_goal.dart';
import '../../shared/art/best_moment_demo.dart';
import '../../shared/route_backdrop.dart';
import '../planner/availability_provider.dart';
import '../routes/watch_export.dart' show WatchBrand, WatchBrandInfo, saveWatchBrand;
import '../../core/i18n.dart';
import '../../shared/language_picker.dart';

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
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => OnboardingScreen()),
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

  void _next() => _pages.nextPage(duration: Duration(milliseconds: 280), curve: Curves.easeOutCubic);

  Future<void> _askLocation() async {
    setState(() => _asking = true);
    await markLocationExplained();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _locationResult = tr('Locatie staat uit op je telefoon. Kadans gebruikt nu je thuisplaats of Barneveld.');
      } else {
        var p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
        _locationResult = p == LocationPermission.denied || p == LocationPermission.deniedForever
            ? tr('Geen probleem. Kadans gebruikt dan het weer van Barneveld; je kunt dit later aanzetten.')
            : tr('Top, het weer klopt nu voor jouw plek.');
      }
    } catch (_) {
      _locationResult = tr('Dat lukte niet. Je kunt het later aanzetten in de instellingen van je telefoon.');
    }
    if (!mounted) return;
    setState(() => _asking = false);
    await Future<void>.delayed(Duration(milliseconds: 900));
    if (mounted) _next();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Page(
        icon: Icons.wb_sunny_outlined,
        art: const BestMomentDemo(),
        title: tr('Loop op het beste moment'),
        text: tr('Strava laat zien wat je gelopen hebt. Kadans zegt wanneer je het best kunt gaan: '
            'op het weer, de wind op jouw route en de buien van het komende uur. En welke kant je op moet en wat je aantrekt.'),
        children: [
          FilledButton(onPressed: _next, child: Text(tr('Verder'))),
        ],
      ),
      _Page(
        icon: Icons.apps_outlined,
        title: tr('Alles op een rij'),
        text: tr('Dit zit er in Kadans. Je vindt het later terug onder de knoppen onderaan, en uitleg onder Ik → Hulp.'),
        children: [
          for (final (icon, name, what) in _features)
            Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 22, color: RwColors.accent),
                SizedBox(width: 12),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${tr(name)}  ', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: tr(what), style: TextStyle(color: RwColors.muted)),
                  ])),
                ),
              ]),
            ),
          SizedBox(height: 8),
          FilledButton(onPressed: _next, child: Text(tr('Verder'))),
        ],
      ),
      _Page(
        icon: Icons.emoji_events_outlined,
        title: tr('Waarvoor loop je?'),
        text: tr('Dan houdt de coach daar rekening mee. Kies je een wedstrijd, dan zet je hem aan het eind meteen in de app.'),
        children: [
          for (final g in RunGoal.values)
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: _Choice(
                label: tr(g.label),
                selected: _goal == g,
                onTap: () async {
                  setState(() => _goal = g);
                  await saveRunGoal(g);
                  await Future<void>.delayed(Duration(milliseconds: 300));
                  if (mounted) _next();
                },
              ),
            ),
          TextButton(onPressed: _next, child: Text(tr('Sla over'))),
        ],
      ),
      _Page(
        icon: Icons.schedule,
        title: tr('Wanneer loop je meestal?'),
        text: tr('Kadans zoekt je beste moment alleen binnen die tijden. Je past ze altijd aan in de weekplanner.'),
        children: [
          for (final (key, label, icon) in _whenChoices)
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: _Choice(
                label: tr(label),
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
            title: Text(tr('Elke ochtend je beste moment als melding')),
            subtitle: Text(tr('Eén melding per dag, geen reclame. Je telefoon vraagt zo om toestemming.'),
                style: TextStyle(color: RwColors.muted)),
            onChanged: (on) async {
              final ok = await NotificationService.instance.setEnabled(on);
              if (mounted) setState(() => _reminder = on && ok);
            },
          ),
          SizedBox(height: 4),
          FilledButton(onPressed: _next, child: Text(_when == null && !_reminder ? tr('Sla over') : tr('Verder'))),
        ],
      ),
      _Page(
        icon: Icons.my_location,
        title: tr('Het weer op jouw plek'),
        text: tr('Daarvoor vraagt Kadans je locatie, alleen terwijl je de app gebruikt. We bewaren hooguit een '
            'grove thuisplaats (op ongeveer 1 km afgerond) en delen je locatie met niemand, tenzij je zelf live delen aanzet.'),
        children: [
          if (_locationResult != null)
            Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(_locationResult!, textAlign: TextAlign.center, style: TextStyle(color: RwColors.good)),
            ),
          FilledButton.icon(
            onPressed: _asking || _locationResult != null ? null : _askLocation,
            icon: _asking
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.location_on_outlined),
            label: Text(tr('Locatie toestaan')),
          ),
          TextButton(
            onPressed: () async {
              await markLocationExplained();
              _next();
            },
            child: Text(tr('Later')),
          ),
        ],
      ),
      _Page(
        icon: Icons.watch_outlined,
        title: tr('Welk horloge heb je?'),
        text: tr('Dan zet Kadans je route met één knop op je horloge, met een trilling bij elke afslag. '
            'Geen horloge? Dan zegt je telefoon de afslagen.'),
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
                    await Future<void>.delayed(Duration(milliseconds: 350));
                    if (mounted) _next();
                  },
                ),
            ],
          ),
          SizedBox(height: 8),
          TextButton(onPressed: _next, child: Text(tr('Later kiezen'))),
        ],
      ),
      _Page(
        icon: Icons.sync,
        title: tr('Werkt naast Strava'),
        text: tr('Koppel Strava voor je oude runs en routes, en je horloge (via Health Connect) voor nieuwe runs. '
            'Dan leert Kadans bij welk weer jij het snelst loopt. Strava blijft voor je kudos; Kadans plant je volgende run.'),
        children: [
          if (_goal == RunGoal.race) ...[
            FilledButton(
              onPressed: () => Navigator.pop(context, OnboardingNext.race),
              child: Text(tr('Mijn wedstrijd toevoegen')),
            ),
            SizedBox(height: 8),
          ],
          if (_goal == RunGoal.race)
            OutlinedButton(
              onPressed: () => Navigator.pop(context, OnboardingNext.connect),
              child: Text(tr('Strava of horloge koppelen')),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(context, OnboardingNext.connect),
              child: Text(tr('Strava of horloge koppelen')),
            ),
          SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, OnboardingNext.route),
            child: Text(tr('Eerst een rondje maken')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, OnboardingNext.today),
            child: Text(tr('Naar mijn beste moment van vandaag')),
          ),
        ],
      ),
    ];

    // Terugknop van Android: eerst een stap terug in de rondleiding, pas op de eerste stap sluiten.
    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _page > 0) {
          _pages.previousPage(duration: Duration(milliseconds: 280), curve: Curves.easeOutCubic);
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
                  tween: Tween(begin: MediaQuery.disableAnimationsOf(context) ? 1 : 0, end: 1),
                  duration: Duration(milliseconds: 1400),
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
                duration: Duration(milliseconds: 200),
                child: IconButton(
                  tooltip: tr('Vorige'),
                  icon: Icon(Icons.arrow_back),
                  onPressed: _page > 0
                      ? () => _pages.previousPage(duration: Duration(milliseconds: 280), curve: Curves.easeOutCubic)
                      : null,
                ),
              ),
              Spacer(),
              const LanguageButton(),
              TextButton(
                onPressed: () async {
                  await markLocationExplained();
                  if (context.mounted) Navigator.pop(context, OnboardingNext.today);
                },
                child: Text(tr('Overslaan')),
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
              padding: EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    GestureDetector(
                      onTap: () => _pages.animateToPage(i, duration: Duration(milliseconds: 280), curve: Curves.easeOutCubic),
                      child: AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      margin: EdgeInsets.symmetric(horizontal: 4),
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
  const _Page({required this.icon, required this.title, required this.text, required this.children, this.art});
  final IconData icon;

  /// Eigen plaatje/animatie in plaats van het icoon.
  final Widget? art;
  final String title;
  final String text;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        // Tekst bovenaan, knoppen onderaan binnen bereik van je duim; scrollt op kleine schermen.
        builder: (context, box) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(28, 0, 28, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 12),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Spacer(),
                  if (art != null) art! else Center(
                    child: Container(
                      width: 168,
                      height: 168,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          RwColors.accent.withValues(alpha: 0.35),
                          RwColors.accentDeep.withValues(alpha: 0.08),
                          Colors.transparent,
                        ], stops: [0, 0.7, 1]),
                      ),
                      child: Icon(icon, size: 76, color: RwColors.accent),
                    ),
                  ),
                  SizedBox(height: 36),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 32, fontWeight: FontWeight.w800, height: 1.1)),
                  SizedBox(height: 16),
                  Text(text, textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted, fontSize: 16, height: 1.5)),
                  Spacer(flex: 2),
                  SizedBox(height: 24),
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
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 20, color: RwColors.accent), SizedBox(width: 12)],
              Expanded(child: Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              if (selected) Icon(Icons.check_circle, size: 20, color: RwColors.accent),
            ]),
          ),
        ),
      );
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/location_service.dart';
import '../../data/services/notification_service.dart';
import '../../domain/availability.dart';
import '../../domain/run_goal.dart';
import '../../domain/start_time_scoring.dart';
import '../../shared/kadans_voice_chooser.dart';
import '../../shared/language_picker.dart';
import '../../shared/widgets.dart';
import '../dashboard/dashboard_providers.dart';
import '../planner/availability_provider.dart';
import '../planner/roster_screen.dart' show openRosterScreen;
import '../profile/member_card.dart';

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

// Vaste donker-goud kleuren: welkom en ledenkaart zijn altijd donker, ook als de app licht staat
// (net als Premium, de ledenkaart en de voet van kadans.fit).
const _ink = Color(0xFF13110E);
const _inkHigh = Color(0xFF2A2219);
const _cream = Color(0xFFF1E9DC);
const _creamSoft = Color(0xFFBDB1A0);
const _gold = Color(0xFFD9BF92);

/// Rondleiding bij de eerste keer openen, in de stijl van kadans.fit:
/// welkom (donker-goud) → drie korte vragen → coachstem → je eerste advies, live → je ledenkaart.
/// Elke stap is over te slaan; ook later terug te zien via Ik → Hulp.
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
  bool _voicePicked = false;

  static const _count = 6;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    _pages.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  void _back() => _pages.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);

  Future<void> _skip() async {
    await markLocationExplained();
    if (mounted) Navigator.pop(context, OnboardingNext.today);
  }

  bool get _darkPage => _page == 0 || _page == _count - 1;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _WelcomePage(onStart: _next),
      _QuestionPage(
        number: 1,
        title: tr('Waarvoor loop je?'),
        text: tr('Dan houdt de coach daar rekening mee. Kies je een wedstrijd, dan zet je hem aan het eind meteen in de app.'),
        children: [
          for (final g in RunGoal.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Choice(
                label: tr(g.label),
                selected: _goal == g,
                onTap: () async {
                  setState(() => _goal = g);
                  await saveRunGoal(g);
                  await Future<void>.delayed(const Duration(milliseconds: 300));
                  if (mounted) _next();
                },
              ),
            ),
          const SizedBox(height: 8),
          KadansButton(label: _goal == null ? tr('Sla over') : tr('Verder'), onPressed: _next),
        ],
      ),
      _QuestionPage(
        number: 2,
        title: tr('Wanneer loop je meestal?'),
        text: tr('Kadans zoekt je beste moment alleen binnen die tijden. Je past ze altijd aan in de weekplanner.'),
        children: [
          for (final (key, label, icon) in _whenChoices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
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
          // Diensten? Dan meteen je rooster koppelen: Kadans plant dan nooit een run tijdens je dienst.
          if (_when == 'altijd')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                onPressed: () => openRosterScreen(context),
                icon: const Icon(Icons.event_busy_outlined),
                label: Text(tr('Koppel je rooster: nooit een run tijdens je dienst')),
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
          const SizedBox(height: 4),
          KadansButton(label: _when == null && !_reminder ? tr('Sla over') : tr('Verder'), onPressed: _next),
        ],
      ),
      _QuestionPage(
        number: 3,
        title: tr('Kies je coachstem'),
        text: tr('Deze stem praat tijdens het lopen: tempo, afstand en afslagen. Tik op de afspeelknop voor een kort voorbeeld. '
            'Je wisselt later altijd bij Opnemen → Stem.'),
        children: [
          KadansVoiceChooser(onPicked: (_) => setState(() => _voicePicked = true)),
          const SizedBox(height: 8),
          KadansButton(label: _voicePicked ? tr('Verder') : tr('Later kiezen'), onPressed: _next),
        ],
      ),
      _AdvicePage(onNext: _next, active: _page == 4),
      _MemberPage(
        goal: _goal,
        onDone: (next) => Navigator.pop(context, next),
      ),
    ];

    final dark = _darkPage;
    final fg = dark ? _cream : RwColors.text;
    final soft = dark ? _creamSoft : RwColors.muted;

    // Terugknop van Android: eerst een stap terug in de rondleiding, pas op de eerste stap sluiten.
    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _page > 0) _back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark || RwColors.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: dark ? _ink : RwColors.background,
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 420),
            color: dark ? _ink : RwColors.background,
            child: SafeArea(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                  child: Row(children: [
                    AnimatedOpacity(
                      opacity: _page > 0 ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: IconButton(
                        tooltip: tr('Vorige'),
                        icon: Icon(Icons.arrow_back, color: fg),
                        onPressed: _page > 0 ? _back : null,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${(_page + 1).toString().padLeft(2, '0')} / ${_count.toString().padLeft(2, '0')}',
                        style: SectionLabel.style(color: soft),
                      ),
                    ),
                    if (_page == 0) Theme(data: Theme.of(context).copyWith(iconTheme: IconThemeData(color: fg)), child: const LanguageButton()),
                    if (_page < _count - 1)
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: soft),
                        onPressed: _skip,
                        child: Text(tr('Later')),
                      ),
                  ]),
                ),
                // Dunne gouden lijn die meegroeit met je voortgang.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: LayoutBuilder(
                    builder: (context, c) => Stack(children: [
                      Container(height: 1, color: (dark ? _gold : RwColors.accent).withValues(alpha: 0.18)),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                        height: 1,
                        width: c.maxWidth * (_page + 1) / _count,
                        color: dark ? _gold : RwColors.accent,
                      ),
                    ]),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (i) => setState(() => _page = i),
                    children: pages,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

bool _still(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Laat een stuk inhoud zacht omhoog en in beeld komen, met vertraging (zoals op kadans.fit).
class _Rise extends StatelessWidget {
  const _Rise({required this.child, this.delay = 0, this.distance = 18});
  final Widget child;
  final int delay;
  final double distance;

  @override
  Widget build(BuildContext context) {
    if (_still(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 800 + delay),
      curve: Interval(delay / (800 + delay), 1, curve: Curves.easeOutCubic),
      builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, distance * (1 - t)), child: c)),
      child: child,
    );
  }
}

/// 1 · Welkom: de gouden K licht op, één zin, één knop.
class _WelcomePage extends StatefulWidget {
  const _WelcomePage({required this.onStart});
  final VoidCallback onStart;

  @override
  State<_WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<_WelcomePage> with SingleTickerProviderStateMixin {
  late final _glow = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_still(context) && !_glow.isAnimating) _glow.repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = _still(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(0, -0.3), radius: 1.1, colors: [_inkHigh, _ink], stops: [0, 0.62]),
      ),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 28),
            child: IntrinsicHeight(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Spacer(),
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: still ? 1 : 0, end: 1),
                    duration: const Duration(milliseconds: 1400),
                    curve: Curves.easeOutCubic,
                    builder: (_, t, c) => Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Transform.scale(scale: 0.86 + 0.14 * t, child: c),
                    ),
                    child: AnimatedBuilder(
                      animation: _glow,
                      builder: (_, c) => DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _gold.withValues(alpha: 0.10 + 0.12 * _glow.value),
                              blurRadius: 60 + 30 * _glow.value,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: c,
                      ),
                      child: Image.asset('assets/logo/k_goud.webp', height: 150, semanticLabel: 'Kadans'),
                    ),
                  ),
                ),
                const Spacer(),
                const SizedBox(height: 28),
                _Rise(
                  delay: 700,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${tr('Wij kijken naar het weer.')}\n'),
                      TextSpan(text: tr('Jij loopt.'), style: const TextStyle(color: _gold)),
                    ]),
                    style: const TextStyle(
                        fontFamily: RwFonts.display, fontSize: 38, fontWeight: FontWeight.w800, height: 1.04, letterSpacing: -0.4, color: _cream),
                  ),
                ),
                const SizedBox(height: 14),
                _Rise(
                  delay: 950,
                  child: Text(
                    tr('Drie korte vragen, dan zie je meteen jouw beste moment om te lopen.'),
                    style: const TextStyle(fontSize: 16, height: 1.5, color: _creamSoft),
                  ),
                ),
                const SizedBox(height: 30),
                _Rise(delay: 1200, child: _DarkButton(label: tr('Begin'), onPressed: widget.onStart)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// De Kadans-knop op donker: licht blok + goud vierkant.
class _DarkButton extends StatelessWidget {
  const _DarkButton({required this.label, required this.onPressed, this.icon = Icons.arrow_forward});
  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: Row(children: [
            Expanded(
              child: Material(
                color: _cream,
                borderRadius: BorderRadius.circular(RwRadius.s),
                child: InkWell(
                  borderRadius: BorderRadius.circular(RwRadius.s),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onPressed();
                  },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Text(label.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: SectionLabel.style(color: _ink).copyWith(fontSize: 13, letterSpacing: 2.2)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: _gold,
              borderRadius: BorderRadius.circular(RwRadius.s),
              child: InkWell(
                borderRadius: BorderRadius.circular(RwRadius.s),
                onTap: onPressed,
                child: SizedBox(width: 56, height: 56, child: Icon(icon, color: _ink, size: 22)),
              ),
            ),
          ]),
        ),
      );
}

/// Vragen-pagina in papierstijl: nummer, grote kop, uitleg, keuzes onderin binnen bereik van je duim.
class _QuestionPage extends StatelessWidget {
  const _QuestionPage({required this.number, required this.title, required this.text, required this.children});
  final int number;
  final String title;
  final String text;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 24),
            child: IntrinsicHeight(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 36),
                _Rise(child: SectionLabel(trf('Vraag {n} van 3', {'n': '$number'}), number: number)),
                const SizedBox(height: 14),
                _Rise(
                  delay: 120,
                  child: Text(title,
                      style: TextStyle(
                          fontFamily: RwFonts.display, fontSize: 32, fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -0.3, color: RwColors.text)),
                ),
                const SizedBox(height: 12),
                _Rise(delay: 240, child: Text(text, style: TextStyle(color: RwColors.muted, fontSize: 15.5, height: 1.5))),
                const Spacer(),
                const SizedBox(height: 24),
                _Rise(delay: 360, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
              ]),
            ),
          ),
        ),
      );
}

/// Grote keuzeknop voor de vragen: papier met fijne rand, gekozen = donker blok (zoals de knoppen op de site).
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final darkBlock = RwColors.isDark ? _cream : const Color(0xFF211A14);
    final onBlock = RwColors.isDark ? _ink : _cream;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected ? darkBlock : RwColors.surface,
        borderRadius: BorderRadius.circular(RwRadius.s),
        border: Border.all(color: selected ? darkBlock : RwColors.hairline),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(RwRadius.s),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 20, color: selected ? _gold : RwColors.accent), const SizedBox(width: 12)],
              Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: selected ? onBlock : RwColors.text)),
              ),
              if (selected) const Icon(Icons.check, size: 20, color: _gold),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 5 · Je eerste advies, live: na toestemming voor je locatie bouwt het advies zich op over de sfeerfoto,
/// en de tijd telt op naar jouw beste moment.
class _AdvicePage extends ConsumerStatefulWidget {
  const _AdvicePage({required this.onNext, required this.active});
  final VoidCallback onNext;
  final bool active;

  @override
  ConsumerState<_AdvicePage> createState() => _AdvicePageState();
}

class _AdvicePageState extends ConsumerState<_AdvicePage> {
  bool _asking = false;
  bool _asked = false;
  String? _note;

  Future<void> _ask() async {
    setState(() => _asking = true);
    await markLocationExplained();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _note = tr('Locatie staat uit op je telefoon. Kadans gebruikt nu je thuisplaats of Barneveld.');
      } else {
        var p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
        if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
          _note = tr('Geen probleem. Kadans gebruikt dan het weer van Barneveld; je kunt dit later aanzetten.');
        }
      }
    } catch (_) {
      _note = tr('Dat lukte niet. Je kunt het later aanzetten in de instellingen van je telefoon.');
    }
    ref.invalidate(weatherLocationProvider);
    ref.invalidate(forecastProvider);
    if (mounted) setState(() {
      _asking = false;
      _asked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 34),
          child: IntrinsicHeight(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _PhotoHead(asked: _asked),
              if (_asked)
                Transform.translate(
                  offset: const Offset(0, -70),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _LiveAdvice(note: _note)),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 22, 14, 0),
                  child: Text(
                    tr('Alleen terwijl je de app gebruikt. We bewaren hooguit een grove thuisplaats (afgerond op ~1 km) en delen je locatie met niemand.'),
                    style: TextStyle(color: RwColors.subtle, fontSize: 13, height: 1.45),
                  ),
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _asked
                    ? KadansButton(label: tr('Mooi, verder'), onPressed: widget.onNext)
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        KadansButton(
                          label: _asking ? tr('Even rekenen…') : tr('Toon mijn moment'),
                          icon: Icons.my_location,
                          onPressed: _asking ? null : _ask,
                        ),
                        TextButton(
                          onPressed: () async {
                            await markLocationExplained();
                            setState(() => _asked = true);
                          },
                          child: Text(tr('Zonder locatie verder')),
                        ),
                      ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PhotoHead extends StatelessWidget {
  const _PhotoHead({required this.asked});
  final bool asked;

  @override
  Widget build(BuildContext context) {
    const white = Color(0xFFFFFBF3);
    final still = _still(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(RwRadius.l),
      child: SizedBox(
        height: 300,
        child: Stack(fit: StackFit.expand, children: [
          // De foto zoomt heel langzaam in.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: still ? 1 : 1.12, end: 1),
            duration: const Duration(milliseconds: 2600),
            curve: Curves.easeOutCubic,
            builder: (_, s, c) => Transform.scale(scale: s, child: c),
            child: Image.asset('assets/foto/heide.jpg',
                fit: BoxFit.cover, alignment: const Alignment(0, -0.1), errorBuilder: (_, _, _) => const ColoredBox(color: _inkHigh)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0.05), Colors.transparent],
                stops: const [0, 0.6, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionLabel(tr('Je eerste advies'), number: 4, color: white.withValues(alpha: 0.85)),
              const SizedBox(height: 14),
              _Rise(
                delay: 200,
                child: Text(
                  asked ? tr('Dit is jouw moment.') : tr('Weer op jouw plek.'),
                  style: const TextStyle(
                      fontFamily: RwFonts.display, fontSize: 32, fontWeight: FontWeight.w700, height: 1.04, letterSpacing: -0.3, color: white),
                ),
              ),
              const SizedBox(height: 8),
              _Rise(
                delay: 400,
                child: Text(
                  asked
                      ? tr('Berekend op het weer van de komende uren, de wind en jouw tijden.')
                      : tr('Sta je locatie toe, dan rekent Kadans meteen jouw beste moment uit.'),
                  style: TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w500, color: white.withValues(alpha: 0.92)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// De advieskaart met het echte weer: schuift omhoog over de foto, tijd telt op.
class _LiveAdvice extends ConsumerWidget {
  const _LiveAdvice({this.note});
  final String? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecast = ref.watch(forecastProvider);
    final availability = ref.watch(availabilityProvider).value ?? Availability.always;
    final still = _still(context);
    final card = Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: RwColors.surface,
        borderRadius: BorderRadius.circular(RwRadius.l),
        border: Border.all(color: RwColors.hairline),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: RwColors.isDark ? 0.35 : 0.14), blurRadius: 36, offset: const Offset(0, 18))],
      ),
      child: forecast.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2))),
        ),
        error: (_, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(tr('Het weer laden lukt nu niet. Op Vandaag zie je zo je beste moment.'), style: TextStyle(color: RwColors.muted)),
        ),
        data: (f) {
          if (f.hours.isEmpty) {
            return Text(tr('Het weer laden lukt nu niet. Op Vandaag zie je zo je beste moment.'), style: TextStyle(color: RwColors.muted));
          }
          final planner = StartTimePlanner(forecast: f, profile: ref.watch(insightsProvider), availability: availability);
          final best = planner.bestPrecise(TrainingType.easy) ?? planner.scoreAll(TrainingType.easy).reduce((a, b) => b.score > a.score ? b : a);
          final w = best.weather;
          final now = DateTime.now();
          final day = best.start.day == now.day ? tr('Vandaag') : (best.start.difference(now).inHours < 36 ? tr('Morgen') : Fmt.date(best.start));
          final target = (best.start.hour * 60 + best.start.minute).toDouble();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: SectionLabel(tr('Jouw beste moment'), number: 1, color: RwColors.good)),
              Text('${best.score}', style: TextStyle(fontFamily: RwFonts.display, fontSize: 20, fontWeight: FontWeight.w700, color: RwColors.good)),
            ]),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              CountUpText(
                value: target,
                from: math.max(0, target - 75),
                format: (v) {
                  final m = v.round();
                  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
                },
                style: TextStyle(
                    fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 64, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1.5, color: RwColors.text),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('$day\n${Fmt.temp(w.feelsLike ?? w.temperature)} · ${Fmt.wind(w.windSpeed)}',
                      style: TextStyle(color: RwColors.muted, height: 1.3)),
                ),
              ),
            ]),
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(note!, style: TextStyle(color: RwColors.subtle, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            // Coach in één zin, zoals de stem het straks zegt.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF211A14), borderRadius: BorderRadius.circular(RwRadius.m)),
              child: Row(children: [
                _VoiceWave(still: still),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    trf('“{dag} om {tijd} is jouw moment.”', {'dag': day, 'tijd': Fmt.time(best.start)}),
                    style: const TextStyle(color: _cream, fontSize: 14, height: 1.35),
                  ),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
    if (still) return card;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutCubic,
      builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 90 * (1 - t)), child: c)),
      child: card,
    );
  }
}

/// Vijf gouden streepjes die op en neer gaan: "de coach praat".
class _VoiceWave extends StatefulWidget {
  const _VoiceWave({required this.still});
  final bool still;

  @override
  State<_VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<_VoiceWave> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void initState() {
    super.initState();
    if (!widget.still) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(RwRadius.s)),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 5; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 3,
                height: 18 * (0.35 + 0.65 * (0.5 + 0.5 * math.sin((_c.value - i * 0.15) * 2 * math.pi))),
                decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(2)),
              ),
          ]),
        ),
      );
}

/// 6 · Je ledenkaart (donker-goud): de kaart komt schuin het scherm in en kantelt mee.
class _MemberPage extends ConsumerWidget {
  const _MemberPage({required this.goal, required this.onDone});
  final RunGoal? goal;
  final ValueChanged<OnboardingNext> onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider).value;
    final name = (p?.fullName?.trim().isNotEmpty ?? false) ? p!.fullName!.trim() : (p?.displayName ?? '');
    final first = name.split(' ').first;
    final still = _still(context);
    final link = TextButton.styleFrom(foregroundColor: _creamSoft);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(0, -0.1), radius: 1.1, colors: [_inkHigh, _ink], stops: [0, 0.65]),
      ),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 24),
            child: IntrinsicHeight(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 32),
                SectionLabel(tr('Je ledenkaart'), number: 5, color: _creamSoft),
                const SizedBox(height: 14),
                _Rise(
                  delay: 600,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${tr('Welkom bij de club')}${first.isEmpty ? '.' : ','}\n'),
                      if (first.isNotEmpty) TextSpan(text: '$first.', style: const TextStyle(color: _gold)),
                    ]),
                    style: const TextStyle(fontFamily: RwFonts.display, fontSize: 34, fontWeight: FontWeight.w800, height: 1.05, color: _cream),
                  ),
                ),
                const Spacer(),
                const SizedBox(height: 24),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: still ? 1 : 0, end: 1),
                  duration: const Duration(milliseconds: 1300),
                  curve: Curves.easeOutCubic,
                  builder: (_, t, c) => Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, 120 * (1 - t)),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..rotateX(0.66 * (1 - t))
                          ..rotateZ(-0.1 * (1 - t)),
                        child: c,
                      ),
                    ),
                  ),
                  child: MemberCard(name: name, email: '', runs: 0, km: 0, badges: 0, since: DateTime.now(), premium: p?.isPremium ?? false),
                ),
                const SizedBox(height: 20),
                Text(tr('Je eerste run maakt hem compleet.'),
                    textAlign: TextAlign.center, style: const TextStyle(color: _creamSoft, fontSize: 16, height: 1.5)),
                const Spacer(),
                const SizedBox(height: 24),
                if (goal == RunGoal.race) ...[
                  _DarkButton(label: tr('Mijn wedstrijd toevoegen'), onPressed: () => onDone(OnboardingNext.race)),
                  const SizedBox(height: 8),
                  TextButton(style: link, onPressed: () => onDone(OnboardingNext.today), child: Text(tr('Naar mijn beste moment van vandaag'))),
                ] else
                  _DarkButton(label: tr('Naar Vandaag'), onPressed: () => onDone(OnboardingNext.today)),
                Wrap(alignment: WrapAlignment.center, children: [
                  TextButton(style: link, onPressed: () => onDone(OnboardingNext.connect), child: Text(tr('Strava of horloge koppelen'))),
                  TextButton(style: link, onPressed: () => onDone(OnboardingNext.route), child: Text(tr('Eerst een rondje maken'))),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

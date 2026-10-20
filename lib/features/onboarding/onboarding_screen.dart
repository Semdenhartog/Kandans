import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../data/services/location_service.dart';

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
enum OnboardingNext { today, connect, route }

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

/// Rondleiding van drie schermen bij de eerste keer openen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _asking = false;
  String? _locationResult;

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
        _locationResult = 'Locatie staat uit op je telefoon. RunWise gebruikt nu je thuisplaats of Barneveld.';
      } else {
        var p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
        _locationResult = p == LocationPermission.denied || p == LocationPermission.deniedForever
            ? 'Geen probleem. RunWise gebruikt dan het weer van Barneveld; je kunt dit later aanzetten.'
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
        text: 'RunWise kijkt naar het weer, de wind op je route en de buien van het komende uur. '
            'Je ziet tot op 5 minuten wanneer je het best kunt gaan, welke kant je op moet en wat je aantrekt.',
        children: [
          FilledButton(onPressed: _next, child: const Text('Verder')),
        ],
      ),
      _Page(
        icon: Icons.my_location,
        title: 'Het weer op jouw plek',
        text: 'Daarvoor vraagt RunWise je locatie, alleen terwijl je de app gebruikt. We bewaren hooguit een '
            'grove thuisplaats (op ongeveer 1 km afgerond) en delen je locatie met niemand, tenzij je zelf live delen aanzet.',
        children: [
          if (_locationResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_locationResult!, textAlign: TextAlign.center, style: const TextStyle(color: RwColors.good)),
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
        title: 'Je runs vanzelf binnen',
        text: 'Koppel Strava of je horloge (via Health Connect). Dan leert RunWise bij welk weer jij het snelst loopt, '
            'en zie je je records, ook gecorrigeerd voor het weer.',
        children: [
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

    return Scaffold(
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
                    painter: _RouteBackdrop(progress: intro * (0.38 + page * 0.31).clamp(0.0, 1.0)),
                  ),
                );
              },
            ),
          ),
        ),
        SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await markLocationExplained();
                  if (context.mounted) Navigator.pop(context, OnboardingNext.today);
                },
                child: const Text('Overslaan'),
              ),
            ),
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
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? RwColors.accent : RwColors.bar,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      ]),
    );
  }
}

class _RouteBackdrop extends CustomPainter {
  _RouteBackdrop({required this.progress});
  final double progress;

  Path _route(Size s) {
    final w = s.width, h = s.height;
    return Path()
      // Blijft buiten de tekstband in het midden: onderlangs, rechts omhoog, bovenlangs.
      ..moveTo(w * 0.04, h * 0.84)
      ..cubicTo(w * 0.20, h * 0.70, w * 0.55, h * 0.78, w * 0.80, h * 0.71)
      ..cubicTo(w * 1.02, h * 0.64, w * 0.98, h * 0.42, w * 0.93, h * 0.30)
      ..cubicTo(w * 0.86, h * 0.12, w * 0.55, h * 0.18, w * 0.40, h * 0.10)
      ..cubicTo(w * 0.28, h * 0.04, w * 0.12, h * 0.10, w * 0.06, h * 0.20);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _route(size);
    final metric = path.computeMetrics().first;
    // Hele route heel zacht als "nog te lopen".
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.05),
    );
    final len = metric.length * progress.clamp(0.0, 1.0);
    if (len <= 1) return;
    final done = metric.extractPath(0, len);
    final shader = ui.Gradient.linear(
      Offset(0, size.height),
      Offset(size.width, 0),
      [RwColors.accentDeep.withValues(alpha: 0.15), RwColors.accent.withValues(alpha: 0.55)],
    );
    canvas.drawPath(
      done,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = RwColors.accent.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(
      done,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
    final tip = metric.getTangentForOffset(len)?.position;
    if (tip != null) {
      canvas.drawCircle(tip, 14, Paint()..color = RwColors.accent.withValues(alpha: 0.18));
      canvas.drawCircle(tip, 5.5, Paint()..color = RwColors.accent);
      canvas.drawCircle(tip, 2.2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _RouteBackdrop old) => old.progress != progress;
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
                  Text(text, textAlign: TextAlign.center, style: const TextStyle(color: RwColors.muted, fontSize: 16, height: 1.5)),
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

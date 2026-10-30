import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Weergave: volg de telefoon, of altijd licht (Zand) of altijd donker (Zand avond).
enum Appearance {
  system('Automatisch'),
  light('Licht'),
  dark('Donker');

  const Appearance(this.label);
  final String label;
}

/// Bewaart de gekozen weergave en zet de juiste kleuren klaar.
class AppearanceController extends ChangeNotifier {
  AppearanceController._();
  static final instance = AppearanceController._();
  static const _key = 'appearance';

  Appearance _mode = Appearance.system;
  Appearance get mode => _mode;

  /// Met welk tabblad de app opent: /today, /runs of /routes.
  static const startTabs = {'/today': 'Vandaag', '/runs': 'Runs', '/routes': 'Routes'};
  String _startTab = '/today';
  String get startTab => _startTab;

  Future<void> setStartTab(String tab) async {
    if (!startTabs.containsKey(tab)) return;
    _startTab = tab;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString('start_tab', tab);
    } catch (_) {}
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_key);
      _mode = Appearance.values.firstWhere((a) => a.name == v, orElse: () => Appearance.system);
      final tab = p.getString('start_tab');
      if (tab != null && startTabs.containsKey(tab)) _startTab = tab;
    } catch (_) {}
    apply(PlatformDispatcher.instance.platformBrightness);
  }

  Future<void> set(Appearance mode) async {
    _mode = mode;
    apply(PlatformDispatcher.instance.platformBrightness);
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, mode.name);
    } catch (_) {}
  }

  /// Kleurenset voor deze weergave en de stand van de telefoon.
  RwPalette paletteFor(Brightness platform) => switch (_mode) {
        Appearance.light => rwZand,
        Appearance.dark => rwZandAvond,
        Appearance.system => platform == Brightness.dark ? rwZandAvond : rwZand,
      };

  /// Zet de kleuren; true als ze veranderd zijn.
  bool apply(Brightness platform) {
    final p = paletteFor(platform);
    if (identical(p, RwColors.palette)) return false;
    RwColors.use(p);
    return true;
  }
}

/// Bouwt alle schermen opnieuw op (na het wisselen van licht/donker), zonder dat je je plek kwijtraakt.
void rebuildAllChildren(BuildContext context) {
  void rebuild(Element el) {
    el.markNeedsBuild();
    el.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}

/// Het Kadans-logo in de kleur van de huidige weergave.
/// Het Kadans-logo als één woord: de K van het logo met "ADANS" erachter, op de voet van de K (geen dubbele K).
/// [height] is de hoogte van de K. Standaard de gouden K; met [mark] een eigen K (bijv. ingekleurd).
Widget kadansLockup({required double height, Widget? mark, Color? color}) {
  final textHeight = height * 0.42;
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      mark ?? Image.asset('assets/logo/k_goud.webp', height: height, excludeFromSemantics: true),
      SizedBox(width: textHeight * 0.56),
      kadansImage('assets/logo/adans.png', height: textHeight, color: color),
    ],
  );
}

Widget kadansImage(String asset, {double? width, double? height, Color? color, String? semanticLabel}) => Image.asset(
      asset,
      width: width,
      height: height,
      color: color ?? RwColors.text,
      colorBlendMode: BlendMode.srcIn,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );

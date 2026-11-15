import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/route_anim.dart';
import 'splits_card.dart' show runFastColor, runSlowColor;

/// Kleuren en gegevens van de routevideo; de tekening zelf staat in route_anim_painter.dart.
const raInk = Color(0xFF1A1410);
const raCream = Color(0xFFF1E9DC);
const raGold = Color(0xFFD9BF92);
const raHot = Color(0xFFFFF3D6);
const raAmber = Color(0xFFE4A046);
const raMute = Color(0xFFA39280);

/// Kleur van een stuk op tempo: [x] 0 = langzaamst, 1 = snelst (blauw, goud, rood). Gelijk in de lijn en de legenda.
Color routeAnimPaceColor(double x) =>
    x < 0.5 ? Color.lerp(runSlowColor, raGold, x * 2)! : Color.lerp(raGold, runFastColor, (x - 0.5) * 2)!;

/// Vaste ontwerpmaat van de video; alles wordt hierin getekend en daarna geschaald naar het beeld.
const routeAnimDesign = Size(1080, 1920);

/// Wat de video laat zien.
class RouteAnimData {
  const RouteAnimData({
    required this.path,
    required this.label,
    required this.meters,
    required this.seconds,
    required this.pathMeters,
    this.trimStartMeters = 0,
    this.spans = const [],
    this.slowPace,
    this.fastPace,
    this.logo,
    this.background,
    this.layout = RouteAnimLayout.none,
  });

  final RoutePath path;
  final String label;

  /// Hele run (voor de cijfers) en de getoonde lijn (zonder privacyzone), in meters en seconden.
  final double meters;
  final double seconds;
  final double pathMeters;

  /// Meters van de run die niet getoond worden aan het begin (privacyzone), voor de kilometerstippen.
  final double trimStartMeters;

  /// Tempo-stukken over de lijn (leeg = standaardkleuren) en traagste/snelste tempo in s/km.
  final List<PaceSpan> spans;
  final double? slowPace;
  final double? fastPace;
  final ui.Image? logo;

  /// Eigen foto achter de lijn (met donkere laag erover voor de leesbaarheid); null = effen donker.
  final ui.Image? background;

  /// Verschuiving van label, cijfers en logo.
  final RouteAnimLayout layout;

  RouteAnimData copyWith({RouteAnimLayout? layout}) => RouteAnimData(
        path: path,
        label: label,
        meters: meters,
        seconds: seconds,
        pathMeters: pathMeters,
        trimStartMeters: trimStartMeters,
        spans: spans,
        slowPace: slowPace,
        fastPace: fastPace,
        logo: logo,
        background: background,
        layout: layout ?? this.layout,
      );
}


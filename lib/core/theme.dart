import 'package:flutter/material.dart';

/// Kleuren uit het Figma-ontwerp "RunWise – App design" (variabelen kleur/…).
class RwColors {
  // Figma-variabelen
  static const achtergrond = Color(0xFFF4F6F5); // kleur/achtergrond
  static const oppervlak = Color(0xFFFFFFFF); // kleur/oppervlak
  static const rand = Color(0xFFE1E6E3); // kleur/rand
  static const tekst = Color(0xFF15201B); // kleur/tekst
  static const tekstZacht = Color(0xFF5B6862); // kleur/tekst-zacht
  static const primair = Color(0xFF0B6E4F); // kleur/primair
  static const primairZacht = Color(0xFFD7F2E6); // kleur/primair-zacht
  static const opPrimair = Color(0xFFFFFFFF); // kleur/op-primair
  static const oranje = Color(0xFFFF7A2F); // kleur/accent
  static const oranjeZacht = Color(0xFFFFE8DA); // kleur/accent-zacht
  static const slotNormaal = Color(0xFFC9D3CE); // kleur/slot-normaal

  // Namen die de bestaande schermen gebruiken, gekoppeld aan het nieuwe palet.
  static const background = achtergrond;
  static const surface = oppervlak;
  static const surfaceHigh = Color(0xFFEEF2F0);
  static const border = rand;
  static const accent = primair;
  static const accentDark = opPrimair;
  static const text = tekst;
  static const muted = tekstZacht;
  static const subtle = Color(0xFF7D8A84);
  static const bar = slotNormaal;
  static const danger = Color(0xFFD64545);
  static const warning = oranje;
}

/// Hoekradius uit Figma (hoek/8, /12, /16, /24, rond).
class RwRadius {
  static const r8 = 8.0;
  static const r12 = 12.0;
  static const r16 = 16.0;
  static const r24 = 24.0;
  static const rond = 999.0;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: RwColors.primair,
    brightness: Brightness.light,
  ).copyWith(
    primary: RwColors.primair,
    onPrimary: RwColors.opPrimair,
    secondary: RwColors.oranje,
    onSecondary: RwColors.opPrimair,
    surface: RwColors.oppervlak,
    onSurface: RwColors.tekst,
    error: RwColors.danger,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: RwColors.achtergrond,
    fontFamily: 'Roboto',
  );

  OutlineInputBorder outline(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(RwRadius.r16),
        borderSide: BorderSide(color: c, width: w),
      );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: RwColors.tekst, displayColor: RwColors.tekst),
    appBarTheme: const AppBarTheme(
      backgroundColor: RwColors.achtergrond,
      foregroundColor: RwColors.tekst,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: RwColors.tekst),
    ),
    cardTheme: CardThemeData(
      color: RwColors.oppervlak,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RwRadius.r24),
        side: const BorderSide(color: RwColors.rand),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RwColors.oppervlak,
      labelStyle: const TextStyle(color: RwColors.tekstZacht),
      hintStyle: const TextStyle(color: RwColors.subtle),
      border: outline(RwColors.rand),
      enabledBorder: outline(RwColors.rand),
      focusedBorder: outline(RwColors.primair, 1.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: RwColors.primair,
        foregroundColor: RwColors.opPrimair,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: RwColors.primair,
        backgroundColor: RwColors.oppervlak,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        side: const BorderSide(color: RwColors.rand, width: 1),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: RwColors.primair),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: RwColors.primair,
      foregroundColor: RwColors.opPrimair,
      shape: StadiumBorder(),
    ),
    chipTheme: const ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: RwColors.rand)),
      backgroundColor: RwColors.oppervlak,
      selectedColor: RwColors.primair,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: RwColors.tekst),
      showCheckmark: false,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RwColors.tekst,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    dividerTheme: const DividerThemeData(color: RwColors.rand),
    dialogTheme: const DialogThemeData(backgroundColor: RwColors.oppervlak),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: RwColors.oppervlak,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: RwColors.primair),
  );
}

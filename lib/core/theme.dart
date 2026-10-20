import 'package:flutter/material.dart';

/// Kleuren van het RunWise-logo: oranje verloop op bijna-zwart.
class RwColors {
  static const background = Color(0xFF09090B);
  static const surface = Color(0xFF141417);
  static const surfaceHigh = Color(0xFF1C1C20);
  static const border = Color(0xFF29292F);

  /// Logo-oranje (midden van het verloop). Tekst erop: [accentDark].
  static const accent = Color(0xFFFD8A26);

  /// Begin en eind van het logo-verloop, voor accenten.
  static const accentDeep = Color(0xFFFD3D22);
  static const accentLight = Color(0xFFFD9E28);
  static const accentDark = Color(0xFF09090B);

  static const text = Color(0xFFF4F4F5);
  static const muted = Color(0xFFBDBDC6);
  static const subtle = Color(0xFF8D8D98);
  static const bar = Color(0xFF323238);

  /// Status: goed (groen), let op (geel), slecht (rood). Bewust anders dan het merk-oranje.
  static const good = Color(0xFF4ADE80);
  static const danger = Color(0xFFFF5470);
  static const warning = Color(0xFFF5C542);
}

/// Lettertypes: Saira voor koppen en grote getallen (past bij het logo),
/// DM Sans voor alle gewone tekst. Meegeleverd in assets/fonts (OFL-licentie).
class RwFonts {
  static const display = 'Saira';
  static const body = 'DMSans';
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: RwColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: RwColors.accent,
    onPrimary: RwColors.accentDark,
    secondary: RwColors.accent,
    onSecondary: RwColors.accentDark,
    surface: RwColors.surface,
    onSurface: RwColors.text,
    error: RwColors.danger,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: RwColors.background,
    fontFamily: RwFonts.body,
  );
  TextStyle? display(TextStyle? s) => s?.copyWith(fontFamily: RwFonts.display, fontWeight: FontWeight.w800);

  return base.copyWith(
    textTheme: base.textTheme
        .copyWith(
          displayLarge: display(base.textTheme.displayLarge),
          displayMedium: display(base.textTheme.displayMedium),
          displaySmall: display(base.textTheme.displaySmall),
          headlineLarge: display(base.textTheme.headlineLarge),
          headlineMedium: display(base.textTheme.headlineMedium),
          headlineSmall: display(base.textTheme.headlineSmall),
        )
        .apply(bodyColor: RwColors.text, displayColor: RwColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: RwColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: RwColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: RwFonts.display,
        fontWeight: FontWeight.w800,
        fontSize: 24,
        color: RwColors.text,
        letterSpacing: -0.3,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: RwColors.muted,
      titleTextStyle: TextStyle(fontFamily: RwFonts.body, fontSize: 16, fontWeight: FontWeight.w600, color: RwColors.text),
      subtitleTextStyle: TextStyle(fontFamily: RwFonts.body, fontSize: 13, color: RwColors.subtle, height: 1.35),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: RwColors.surfaceHigh,
      selectedColor: RwColors.accent,
      side: const BorderSide(color: RwColors.border),
      labelStyle: const TextStyle(fontFamily: RwFonts.body, fontWeight: FontWeight.w600, color: RwColors.text),
      secondaryLabelStyle: const TextStyle(fontFamily: RwFonts.body, fontWeight: FontWeight.w600, color: RwColors.accentDark),
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStateProperty.all(const TextStyle(fontFamily: RwFonts.body, fontWeight: FontWeight.w600)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: RwColors.accent,
        textStyle: const TextStyle(fontFamily: RwFonts.body, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    cardTheme: CardThemeData(
      color: RwColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: RwColors.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: RwColors.surface,
      indicatorColor: RwColors.accent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? RwColors.accentDark
              : RwColors.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: RwFonts.body,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? RwColors.text : RwColors.muted,
        ),
      ),
      height: 68,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RwColors.surfaceHigh,
      labelStyle: const TextStyle(color: RwColors.muted),
      hintStyle: const TextStyle(color: RwColors.subtle),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: RwColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: RwColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: RwColors.accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: RwColors.accent,
        foregroundColor: RwColors.accentDark,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: RwFonts.body, fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: RwColors.text,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        side: const BorderSide(color: RwColors.border, width: 1.5),
        textStyle: const TextStyle(fontFamily: RwFonts.body, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: RwColors.accent,
      foregroundColor: RwColors.accentDark,
      elevation: 2,
      highlightElevation: 4,
      extendedTextStyle: TextStyle(fontFamily: RwFonts.body, fontWeight: FontWeight.w700, fontSize: 16),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RwColors.surfaceHigh,
      contentTextStyle: TextStyle(fontFamily: RwFonts.body, color: RwColors.text),
    ),
    dividerTheme: const DividerThemeData(color: RwColors.border),
  );
}

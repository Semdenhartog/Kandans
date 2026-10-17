import 'package:flutter/material.dart';

/// Kleuren overgenomen van de RunWise-landingspagina.
class RwColors {
  static const background = Color(0xFF0E1714);
  static const surface = Color(0xFF16231F);
  static const surfaceHigh = Color(0xFF1D2C27);
  static const border = Color(0xFF263731);
  static const accent = Color(0xFFC9F25B);
  static const accentDark = Color(0xFF0E1714);
  static const text = Color(0xFFE9EFEA);
  static const muted = Color(0xFFB7C4BC);
  static const subtle = Color(0xFF8FA198);
  static const bar = Color(0xFF2F433B);
  static const danger = Color(0xFFFF7A6B);
  static const warning = Color(0xFFFFC857);
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
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: RwColors.text,
      displayColor: RwColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: RwColors.background,
      foregroundColor: RwColors.text,
      elevation: 0,
      centerTitle: false,
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
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, color: RwColors.muted),
      ),
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
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: RwColors.text,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        side: const BorderSide(color: RwColors.border, width: 1.5),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: RwColors.accent,
      foregroundColor: RwColors.accentDark,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RwColors.surfaceHigh,
      contentTextStyle: TextStyle(color: RwColors.text),
    ),
    dividerTheme: const DividerThemeData(color: RwColors.border),
  );
}

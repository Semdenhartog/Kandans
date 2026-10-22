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
/// Cijfers even breed (Saira heeft 'tnum'), zodat tijden en tempo's niet verspringen als ze veranderen.
const rwTnum = <FontFeature>[FontFeature.tabularFigures()];

/// Vaste tekststijlen, zodat koppen, labels en cijfers overal hetzelfde zijn.
class RwText {
  /// Sectiekop in hoofdletters, met ruime spatiëring (zoals in horloges en luxe-apps).
  static const overline = TextStyle(
    fontFamily: RwFonts.body,
    fontSize: 12,
    color: RwColors.subtle,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
  );

  /// Grote kop van een scherm of blad.
  static const title = TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 24, fontWeight: FontWeight.w800, height: 1.15);

  /// Groot getal (afstand, tijd).
  static const number = TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 28, fontWeight: FontWeight.w800, height: 1);

  /// Klein label onder een getal.
  static const label = TextStyle(fontFamily: RwFonts.body, fontSize: 12, color: RwColors.subtle);
}

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
  TextStyle? display(TextStyle? s) => s?.copyWith(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontFeatures: rwTnum);

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
      // Doorzichtig, zodat de aura bovenin doorschijnt (de schermen zelf hebben hun eigen achtergrond).
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: RwColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: RwFonts.display,
        fontFeatures: rwTnum,
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
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? RwColors.accent : RwColors.surface),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? RwColors.accentDark : RwColors.text),
        iconColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? RwColors.accentDark : RwColors.muted),
        side: WidgetStateProperty.all(const BorderSide(color: RwColors.border)),
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
      // Zelfde rand als RwCard, zodat lijstkaarten (Ik, schema) en RwCards één familie zijn.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x14FFFFFF)),
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
      // Veld licht iets op zodra je erin typt.
      fillColor: WidgetStateColor.resolveWith(
        (st) => st.contains(WidgetState.focused) ? const Color(0xFF221D1A) : RwColors.surfaceHigh,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      labelStyle: const TextStyle(color: RwColors.muted),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (st) => TextStyle(
          color: st.contains(WidgetState.error)
              ? RwColors.danger
              : (st.contains(WidgetState.focused) ? RwColors.accent : RwColors.muted),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      hintStyle: const TextStyle(color: RwColors.subtle),
      prefixIconColor: WidgetStateColor.resolveWith((st) => st.contains(WidgetState.focused) ? RwColors.accent : RwColors.subtle),
      suffixIconColor: WidgetStateColor.resolveWith((st) => st.contains(WidgetState.focused) ? RwColors.accent : RwColors.subtle),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: RwColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: RwColors.accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: RwColors.danger.withValues(alpha: 0.7)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: RwColors.danger, width: 1.6),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: RwColors.accent,
      selectionColor: RwColors.accent.withValues(alpha: 0.3),
      selectionHandleColor: RwColors.accent,
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
      backgroundColor: Color(0xFF26262C),
      elevation: 6,
      shape: StadiumBorder(side: BorderSide(color: Color(0x1FFFFFFF))),
      insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 14),
      contentTextStyle: TextStyle(fontFamily: RwFonts.body, color: RwColors.text, fontWeight: FontWeight.w500),
    ),
    // Vernieuwen (omlaag trekken) en laadlijnen in RunWise-kleuren.
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: RwColors.accent,
      refreshBackgroundColor: RwColors.surfaceHigh,
      linearTrackColor: RwColors.bar,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF151518),
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Color(0xB3000000),
      showDragHandle: true,
      dragHandleColor: Color(0xFF3A3A42),
      dragHandleSize: Size(40, 4),
      // Lichte rand langs de bovenkant: het paneel "zweeft" boven de inhoud.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: Color(0x22FFFFFF)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFF17171B),
      surfaceTintColor: Colors.transparent,
      barrierColor: Color(0xB3000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(26)),
        side: BorderSide(color: Color(0x14FFFFFF)),
      ),
      titleTextStyle: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 22, fontWeight: FontWeight.w800, color: RwColors.text),
      contentTextStyle: TextStyle(fontFamily: RwFonts.body, fontSize: 15, color: RwColors.muted, height: 1.45),
    ),
    dividerTheme: const DividerThemeData(color: RwColors.border),
    // Vloeiende overgangen tussen schermen (vervagen en schuiven, zoals de nieuwste Android-stijl).
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

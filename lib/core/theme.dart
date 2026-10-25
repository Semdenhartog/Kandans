import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Eén kleurenset. Kadans heeft er twee: Zand (licht, overdag) en Zand avond (donker).
class RwPalette {
  const RwPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.hairline,
    required this.accent,
    required this.accentDeep,
    required this.accentLight,
    required this.accentDark,
    required this.text,
    required this.muted,
    required this.subtle,
    required this.bar,
    required this.good,
    required this.danger,
    required this.warning,
    required this.signal,
    required this.sheet,
    required this.snack,
    required this.focusFill,
    required this.scrim,
    required this.shadow,
  });
  final Brightness brightness;
  final Color background, surface, surfaceHigh, border, hairline;
  final Color accent, accentDeep, accentLight, accentDark;
  final Color text, muted, subtle, bar;
  final Color good, danger, warning, signal;
  final Color sheet, snack, focusFill, scrim, shadow;
}

/// Zand: warm zand met brons en espresso. Rustig voor de ogen, goed leesbaar buiten.
const rwZand = RwPalette(
  brightness: Brightness.light,
  background: Color(0xFFEDE6DA),
  surface: Color(0xFFF7F2EA),
  surfaceHigh: Color(0xFFE7DFD2),
  border: Color(0xFFDCD1BF),
  hairline: Color(0x1F3B2C1F),
  accent: Color(0xFF7A5A34),
  accentDeep: Color(0xFF5E4325),
  accentLight: Color(0xFFA27C4A),
  accentDark: Color(0xFFFBF7F0),
  text: Color(0xFF211A13),
  muted: Color(0xFF5A5044),
  subtle: Color(0xFF6C6153),
  bar: Color(0xFFD9CEBC),
  good: Color(0xFF2A6B3F),
  danger: Color(0xFFA93A35),
  warning: Color(0xFF7E5B0E),
  signal: Color(0xFFA44A18),
  sheet: Color(0xFFF7F2EA),
  snack: Color(0xFF2B231B),
  focusFill: Color(0xFFF1EADF),
  scrim: Color(0x8C211A13),
  shadow: Color(0x24402A12),
);

/// Zand avond: de donkere tegenhanger, voor 's avonds en in het donker.
const rwZandAvond = RwPalette(
  brightness: Brightness.dark,
  background: Color(0xFF13110E),
  surface: Color(0xFF1C1814),
  surfaceHigh: Color(0xFF25201B),
  border: Color(0xFF352E26),
  hairline: Color(0x1AF1E9DC),
  accent: Color(0xFFD9BF92),
  accentDeep: Color(0xFFB8955F),
  accentLight: Color(0xFFE8D3AE),
  accentDark: Color(0xFF1A1510),
  text: Color(0xFFF1E9DC),
  muted: Color(0xFFBDB1A0),
  subtle: Color(0xFF94897A),
  bar: Color(0xFF3A332B),
  good: Color(0xFF8CC99A),
  danger: Color(0xFFEF7F78),
  warning: Color(0xFFE6C16A),
  signal: Color(0xFFE0884E),
  sheet: Color(0xFF1A1612),
  snack: Color(0xFF2A241E),
  focusFill: Color(0xFF2B251F),
  scrim: Color(0xB3000000),
  shadow: Color(0x66000000),
);

/// Kleuren van de huidige set. Wisselt mee met licht/donker (zie [RwColors.use]).
class RwColors {
  static RwPalette _p = rwZand;
  static RwPalette get palette => _p;
  static void use(RwPalette p) => _p = p;
  static bool get isDark => _p.brightness == Brightness.dark;

  static Color get background => _p.background;
  static Color get surface => _p.surface;
  static Color get surfaceHigh => _p.surfaceHigh;
  static Color get border => _p.border;

  /// Fijne rand om kaarten en panelen.
  static Color get hairline => _p.hairline;

  /// Merkkleur (brons overdag, champagne 's avonds). Tekst erop: [accentDark].
  static Color get accent => _p.accent;
  static Color get accentDeep => _p.accentDeep;
  static Color get accentLight => _p.accentLight;
  static Color get accentDark => _p.accentDark;

  static Color get text => _p.text;
  static Color get muted => _p.muted;
  static Color get subtle => _p.subtle;
  static Color get bar => _p.bar;

  /// Status: goed, let op, slecht. Bewust anders dan de merkkleur.
  static Color get good => _p.good;
  static Color get danger => _p.danger;
  static Color get warning => _p.warning;

  /// Sportief oranje, alleen voor wat nú gebeurt (opnemen, live delen).
  static Color get signal => _p.signal;
}

/// Lettertypes: Saira voor koppen en grote getallen (past bij het logo),
/// DM Sans voor alle gewone tekst. Meegeleverd in assets/fonts (OFL-licentie).
/// Cijfers even breed (Saira heeft 'tnum'), zodat tijden en tempo's niet verspringen als ze veranderen.
const rwTnum = <FontFeature>[FontFeature.tabularFigures()];

/// Vaste tekststijlen, zodat koppen, labels en cijfers overal hetzelfde zijn.
class RwText {
  /// Sectiekop in hoofdletters, met ruime spatiëring (zoals in horloges en luxe-apps).
  static TextStyle get overline => TextStyle(
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
  static TextStyle get label => TextStyle(fontFamily: RwFonts.body, fontSize: 12, color: RwColors.subtle);
}

class RwFonts {
  static const display = 'Saira';
  static const body = 'DMSans';
}

ThemeData buildTheme() {
  final dark = RwColors.isDark;
  final scheme = ColorScheme.fromSeed(
    seedColor: RwColors.accent,
    brightness: RwColors.palette.brightness,
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
    appBarTheme: AppBarTheme(
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
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
    listTileTheme: ListTileThemeData(
      iconColor: RwColors.muted,
      titleTextStyle: TextStyle(fontFamily: RwFonts.body, fontSize: 16, fontWeight: FontWeight.w600, color: RwColors.text),
      subtitleTextStyle: TextStyle(fontFamily: RwFonts.body, fontSize: 13, color: RwColors.subtle, height: 1.35),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: RwColors.surfaceHigh,
      selectedColor: RwColors.accent,
      side: BorderSide(color: RwColors.border),
      labelStyle: TextStyle(fontFamily: RwFonts.body, fontWeight: FontWeight.w600, color: RwColors.text),
      secondaryLabelStyle: TextStyle(fontFamily: RwFonts.body, fontWeight: FontWeight.w600, color: RwColors.accentDark),
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
        side: WidgetStateProperty.all(BorderSide(color: RwColors.border)),
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
        side: BorderSide(color: RwColors.hairline),
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
        (st) => st.contains(WidgetState.focused) ? RwColors.palette.focusFill : RwColors.surfaceHigh,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      labelStyle: TextStyle(color: RwColors.muted),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (st) => TextStyle(
          color: st.contains(WidgetState.error)
              ? RwColors.danger
              : (st.contains(WidgetState.focused) ? RwColors.accent : RwColors.muted),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      hintStyle: TextStyle(color: RwColors.subtle),
      prefixIconColor: WidgetStateColor.resolveWith((st) => st.contains(WidgetState.focused) ? RwColors.accent : RwColors.subtle),
      suffixIconColor: WidgetStateColor.resolveWith((st) => st.contains(WidgetState.focused) ? RwColors.accent : RwColors.subtle),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: RwColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: RwColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: RwColors.accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: RwColors.danger.withValues(alpha: 0.7)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: RwColors.danger, width: 1.6),
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
        side: BorderSide(color: RwColors.border, width: 1.5),
        textStyle: const TextStyle(fontFamily: RwFonts.body, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: RwColors.accent,
      foregroundColor: RwColors.accentDark,
      elevation: 2,
      highlightElevation: 4,
      extendedTextStyle: TextStyle(fontFamily: RwFonts.body, fontWeight: FontWeight.w700, fontSize: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RwColors.palette.snack,
      elevation: 6,
      shape: StadiumBorder(side: BorderSide(color: RwColors.hairline)),
      insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 14),
      contentTextStyle: TextStyle(fontFamily: RwFonts.body, color: dark ? RwColors.text : const Color(0xFFF7F2EA), fontWeight: FontWeight.w500),
    ),
    // Vernieuwen (omlaag trekken) en laadlijnen in Kadans-kleuren.
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: RwColors.accent,
      refreshBackgroundColor: RwColors.surfaceHigh,
      linearTrackColor: RwColors.bar,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: RwColors.palette.sheet,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: RwColors.palette.scrim,
      showDragHandle: true,
      dragHandleColor: RwColors.border,
      dragHandleSize: Size(40, 4),
      // Lichte rand langs de bovenkant: het paneel "zweeft" boven de inhoud.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: RwColors.hairline),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: RwColors.palette.sheet,
      surfaceTintColor: Colors.transparent,
      barrierColor: RwColors.palette.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(26)),
        side: BorderSide(color: RwColors.hairline),
      ),
      titleTextStyle: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 22, fontWeight: FontWeight.w800, color: RwColors.text),
      contentTextStyle: TextStyle(fontFamily: RwFonts.body, fontSize: 15, color: RwColors.muted, height: 1.45),
    ),
    dividerTheme: DividerThemeData(color: RwColors.border),
    // Vloeiende overgangen tussen schermen (vervagen en schuiven, zoals de nieuwste Android-stijl).
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

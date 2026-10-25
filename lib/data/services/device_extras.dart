import 'package:screen_brightness/screen_brightness.dart';

/// Scherm op volle helderheid (zonmodus) of terug naar wat de gebruiker had.
/// Alleen voor Kadans zelf; de systeeminstelling blijft ongemoeid.
/// Nachtmodus: scherm gedimd (rood beeld komt uit de app zelf), zodat je ogen aan het donker gewend blijven.
Future<void> setNightBrightness(bool on) async {
  try {
    if (on) {
      await ScreenBrightness.instance.setApplicationScreenBrightness(0.15);
    } else {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    }
  } catch (_) {}
}

Future<void> setMaxBrightness(bool on) async {
  try {
    if (on) {
      await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
    } else {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    }
  } catch (_) {
    // Niet elk toestel staat dit toe; zonmodus werkt dan zonder helderheid.
  }
}

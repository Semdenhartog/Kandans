/// Snelkoppeling "Wanneer lopen?" (lang drukken op het app-icoon, of via de spraakassistent):
/// runwise://app/moment opent Vandaag en leest het beste moment voor.
class VoiceShortcut {
  static bool _pending = false;

  static void request() => _pending = true;

  /// Eén keer true na het openen via de snelkoppeling.
  static bool consume() {
    final p = _pending;
    _pending = false;
    return p;
  }
}

/// Vaste animatiesnelheden. Gebruik deze i.p.v. losse `Duration(milliseconds: …)`, zodat het hele
/// scherm even snel aanvoelt. Waarden zijn gelijk aan wat al op meerdere plekken werd gebruikt.
class RwMotion {
  RwMotion._();

  /// Kleine wisselingen (kleur, zichtbaarheid, chip).
  static const fast = Duration(milliseconds: 180);

  /// Standaard (tabbladen, kaarten, schuiven).
  static const normal = Duration(milliseconds: 300);

  /// Rustig (grote delen, tellers).
  static const slow = Duration(milliseconds: 500);
}

// Hartslagherstel (HRR): hoeveel slagen je hartslag daalt in de eerste minuut na het stoppen.
// Een bekende maat voor fitheid; een daling die veel kleiner is dan normaal kan wijzen op vermoeidheid of ziek worden.

class HrrResult {
  const HrrResult({required this.at, required this.startBpm, required this.endBpm});
  final DateTime at;
  final int startBpm;
  final int endBpm;

  int get drop => startBpm - endBpm;

  Map<String, dynamic> toJson() => {'t': at.toIso8601String(), 's': startBpm, 'e': endBpm};

  static HrrResult? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = DateTime.tryParse('${j['t']}');
    final s = (j['s'] as num?)?.toInt(), e = (j['e'] as num?)?.toInt();
    if (t == null || s == null || e == null) return null;
    return HrrResult(at: t, startBpm: s, endBpm: e);
  }
}

/// Oordeel over één meting.
String hrrLevel(int drop) => drop >= 25 ? 'Goed herstel' : (drop >= 12 ? 'Normaal herstel' : 'Traag herstel');

/// Vergelijkt de laatste meting met je eigen gemiddelde (minstens 3 eerdere metingen).
String? hrrTrend(List<HrrResult> all) {
  if (all.length < 4) return null;
  final sorted = [...all]..sort((a, b) => a.at.compareTo(b.at));
  final last = sorted.last;
  final before = sorted.sublist(0, sorted.length - 1).reversed.take(10).toList();
  final avg = before.fold<double>(0, (s, r) => s + r.drop) / before.length;
  if (last.drop <= avg - 8) {
    return 'Je hartslag zakte minder snel dan normaal (${last.drop} tegen gemiddeld ${avg.round()}). Moe, slecht geslapen of ziek aan het worden? Doe het rustig aan.';
  }
  if (last.drop >= avg + 6) return 'Sneller herstel dan je gemiddelde (${avg.round()}): je bent goed in vorm.';
  return 'In lijn met je gemiddelde (${avg.round()} slagen).';
}

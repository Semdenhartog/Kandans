/// Kaarten op Vandaag die je zelf kunt ordenen of verbergen (zoals het ochtendrapport van Garmin).
enum DashCard {
  warnings('Waarschuwingen', 'Onweer, hitte, gladheid, lucht en pollen'),
  clothing('Aantrekken', 'Kledingadvies voor het gekozen moment'),
  rain('Buien komende 2 uur', 'Live van Buienradar'),
  hours('Per uur', 'De loopomstandigheden per uur'),
  routeWind('Wind op je route', 'Alleen als je een route kiest'),
  planner('Weekplanner', 'De beste momenten deze week'),
  month('Maanduitdaging', 'Je doel voor deze maand'),
  live('Veilig onderweg', 'Live je locatie delen');

  const DashCard(this.label, this.description);
  final String label;
  final String description;
}

class DashLayout {
  const DashLayout(this.order, this.hidden);

  static const standard = DashLayout(DashCard.values, {});

  final List<DashCard> order;
  final Set<DashCard> hidden;

  List<DashCard> get visible => [for (final c in order) if (!hidden.contains(c)) c];

  DashLayout move(int from, int to) {
    final list = [...order];
    final c = list.removeAt(from);
    list.insert(to > from ? to - 1 : to, c);
    return DashLayout(list, hidden);
  }

  DashLayout toggle(DashCard c) => DashLayout(order, hidden.contains(c) ? ({...hidden}..remove(c)) : {...hidden, c});

  String encode() => [for (final c in order) '${hidden.contains(c) ? '-' : ''}${c.name}'].join(',');

  /// Leest de opgeslagen indeling; nieuwe kaarten (na een update) komen achteraan.
  static DashLayout decode(String? s) {
    if (s == null || s.isEmpty) return standard;
    final order = <DashCard>[];
    final hidden = <DashCard>{};
    for (final raw in s.split(',')) {
      final off = raw.startsWith('-');
      final name = off ? raw.substring(1) : raw;
      final c = DashCard.values.where((x) => x.name == name).firstOrNull;
      if (c == null || order.contains(c)) continue;
      order.add(c);
      if (off) hidden.add(c);
    }
    for (final c in DashCard.values) {
      if (!order.contains(c)) order.add(c);
    }
    return DashLayout(order, hidden);
  }
}

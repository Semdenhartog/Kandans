/// Kracht- en mobiliteitsroutines voor lopers (eigen RunWise-oefeningen, zonder materiaal).
class Exercise {
  const Exercise(this.name, this.how, {this.seconds = 40, this.perSide = false});
  final String name;
  final String how;
  final int seconds;

  /// Links en rechts: de app doet de oefening twee keer.
  final bool perSide;
}

class Routine {
  const Routine({required this.id, required this.title, required this.subtitle, required this.icon, required this.exercises, this.rest = 15});
  final String id;
  final String title;
  final String subtitle;

  /// Naam van een Material-icoon.
  final String icon;
  final List<Exercise> exercises;

  /// Seconden pauze tussen oefeningen.
  final int rest;

  /// Alle blokken op volgorde (links/rechts uitgeschreven).
  List<({String name, String how, int seconds, String? side})> get blocks => [
        for (final e in exercises)
          if (e.perSide) ...[
            (name: e.name, how: e.how, seconds: e.seconds, side: 'links'),
            (name: e.name, how: e.how, seconds: e.seconds, side: 'rechts'),
          ] else
            (name: e.name, how: e.how, seconds: e.seconds, side: null),
      ];

  int get totalSeconds {
    final b = blocks;
    return b.fold<int>(0, (a, x) => a + x.seconds) + rest * (b.length - 1);
  }

  static const all = <Routine>[
    Routine(
      id: 'warmup',
      title: 'Warming-up',
      subtitle: 'Voor je run: losmaken en opwarmen',
      icon: 'local_fire_department',
      rest: 5,
      exercises: [
        Exercise('Knieheffen op de plaats', 'Rustig joggen op de plaats en je knieën om de beurt optillen tot heuphoogte.', seconds: 30),
        Exercise('Hakken naar billen', 'Op de plaats joggen en je hakken naar je billen tikken.', seconds: 30),
        Exercise('Beenzwaai voor-achter', 'Hand tegen een muur of paal, been ontspannen naar voren en achteren zwaaien.', seconds: 20, perSide: true),
        Exercise('Beenzwaai opzij', 'Met je gezicht naar de muur, been voor je lichaam langs van links naar rechts zwaaien.', seconds: 20, perSide: true),
        Exercise('Enkelrondjes', 'Op één been, met je andere voet rustige rondjes draaien.', seconds: 20, perSide: true),
        Exercise('Uitvalspas met draai', 'Grote stap naar voren, door je knie zakken en je bovenlijf naar het voorste been draaien. Afwisselen.', seconds: 40),
      ],
    ),
    Routine(
      id: 'strength',
      title: 'Kracht voor lopers',
      subtitle: 'Sterkere benen en romp, minder blessures',
      icon: 'fitness_center',
      exercises: [
        Exercise('Squat', 'Voeten op heupbreedte, zak alsof je op een stoel gaat zitten, knieën boven je tenen. Rustig omhoog.'),
        Exercise('Bilbrug', 'Op je rug, knieën gebogen. Duw je heupen omhoog tot je lijf een rechte lijn is, even vasthouden en zakken.'),
        Exercise('Kuitheffen', 'Op de rand van een traptree of plat op de grond: langzaam op je tenen en weer zakken.'),
        Exercise('Uitvalspas', 'Grote stap naar voren, achterste knie bijna op de grond, terug en afwisselen.'),
        Exercise('Eenbenige balans met reiken', 'Op één been, buig voorover en reik met je handen naar de grond, rug recht. Terug omhoog.', seconds: 30, perSide: true),
        Exercise('Plank', 'Op je onderarmen en tenen, lijf recht van hoofd tot hielen. Buik aanspannen en rustig ademen.', seconds: 30),
        Exercise('Zijplank', 'Op één onderarm en de zijkant van je voet, heupen omhoog. Knieën op de grond mag ook.', seconds: 25, perSide: true),
        Exercise('Dead bug', 'Op je rug, armen omhoog en knieën boven je heupen. Strek langzaam tegenovergestelde arm en been, onderrug op de grond.'),
      ],
    ),
    Routine(
      id: 'cooldown',
      title: 'Rekken na je run',
      subtitle: 'Rustig rekken voor kuiten, benen en heupen',
      icon: 'self_improvement',
      rest: 5,
      exercises: [
        Exercise('Kuit', 'Handen tegen een muur, één been ver naar achter met de hak op de grond. Leun rustig naar voren.', seconds: 30, perSide: true),
        Exercise('Achterkant bovenbeen', 'Hak op een lage verhoging, been gestrekt, en kantel vanuit je heup naar voren tot je rek voelt.', seconds: 30, perSide: true),
        Exercise('Voorkant heup', 'Halve knielzit, duw je heup rustig naar voren tot je rek voelt aan de voorkant van je achterste been.', seconds: 30, perSide: true),
        Exercise('Bil (figuur 4)', 'Op je rug, enkel op de andere knie en trek dat been rustig naar je toe.', seconds: 30, perSide: true),
        Exercise('Onderrug', 'Op je rug, knieën naar je borst en zacht heen en weer wiegen.', seconds: 30),
      ],
    ),
  ];
}

/// Speler: houdt bij welk blok bezig is, op tijd.
class RoutinePlayer {
  RoutinePlayer(this.routine);
  final Routine routine;
  late final _blocks = routine.blocks;

  int index = 0;
  bool resting = false;
  double _elapsed = 0;

  bool get finished => index >= _blocks.length;
  ({String name, String how, int seconds, String? side})? get current => finished ? null : _blocks[index];
  ({String name, String how, int seconds, String? side})? get next => index + 1 < _blocks.length ? _blocks[index + 1] : null;
  int get count => _blocks.length;

  double get remaining {
    final c = current;
    if (c == null) return 0;
    return ((resting ? routine.rest : c.seconds) - _elapsed).clamp(0, 999).toDouble();
  }

  String _label(({String name, String how, int seconds, String? side}) b) => b.side == null ? b.name : '${b.name}, ${b.side}';

  /// Tekst om uit te spreken bij de start.
  String get intro => 'We beginnen met ${_label(_blocks.first)}. ${_blocks.first.seconds} seconden.';

  /// Een seconde (of meer) verder. Geeft een tekst als er iets te zeggen is.
  String? tick(double seconds) {
    if (finished) return null;
    final before = remaining;
    _elapsed += seconds;
    if (!resting && before > 3.5 && remaining <= 3.5 && current!.seconds >= 20) return 'Nog drie.';
    if (remaining > 0) return null;
    _elapsed = 0;
    if (!resting && index + 1 < _blocks.length && routine.rest > 0) {
      resting = true;
      return 'Pauze. Hierna: ${_label(_blocks[index + 1])}.';
    }
    resting = false;
    index++;
    if (finished) return 'Klaar! Goed gedaan.';
    return '${_label(current!)}. ${current!.seconds} seconden.';
  }

  /// Naar het volgende blok.
  String? skip() {
    if (finished) return null;
    _elapsed = 0;
    resting = false;
    index++;
    if (finished) return 'Klaar! Goed gedaan.';
    return '${_label(current!)}. ${current!.seconds} seconden.';
  }
}

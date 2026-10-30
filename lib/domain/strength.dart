/// Kracht- en mobiliteitsroutines voor lopers (eigen Kadans-oefeningen, zonder materiaal).
class Exercise {
  const Exercise(this.name, this.how, {this.seconds = 40, this.perSide = false});
  final String name;
  final String how;
  final int seconds;

  /// Links en rechts: de app doet de oefening twee keer.
  final bool perSide;
}

/// Soort routine, voor de indeling op het scherm.
enum RoutineCategory {
  warmup('Warming-up', 'Voor je run: hartslag omhoog, gewrichten los, spieren wakker.'),
  kracht('Kracht', 'Twee keer per week maakt je sneller en minder blessuregevoelig.'),
  mobiliteit('Mobiliteit', 'Soepele heupen, enkels en rug geven een vrijere pas. Mag elke dag.'),
  cooldown('Cooling-down', 'Na je run: rustig worden, rekken en herstellen.');

  const RoutineCategory(this.label, this.intro);
  final String label;
  final String intro;
}

class Routine {
  const Routine({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.exercises,
    this.rest = 15,
    this.category = RoutineCategory.kracht,
    this.note,
  });
  final String id;
  final RoutineCategory category;

  /// Korte waarschuwing of tip, bijv. "alleen als je blessurevrij bent".
  final String? note;
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
    // ---------- Warming-up ----------
    Routine(
      id: 'warmup',
      title: 'Warming-up',
      subtitle: 'Voor elke run: losmaken en opwarmen',
      icon: 'local_fire_department',
      category: RoutineCategory.warmup,
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
      id: 'warmup_kort',
      title: 'Snelle warming-up',
      subtitle: 'Weinig tijd? In drie minuten klaar',
      icon: 'bolt',
      category: RoutineCategory.warmup,
      rest: 3,
      exercises: [
        Exercise('Knieheffen op de plaats', 'Rustig joggen op de plaats en je knieën om de beurt optillen.', seconds: 30),
        Exercise('Heupcirkels', 'Handen in je zij, voeten op heupbreedte. Draai grote rondjes met je heupen, halverwege de andere kant op.', seconds: 20),
        Exercise('Beenzwaai voor-achter', 'Hand tegen een muur, been ontspannen naar voren en achteren zwaaien.', seconds: 15, perSide: true),
        Exercise('Squat naar tenen', 'Zak rustig in een squat, kom omhoog en ga door tot op je tenen. Vloeiend herhalen.', seconds: 30),
        Exercise('Jumping jacks', 'Spring met je benen uit elkaar en je armen boven je hoofd, en weer terug. Licht en veerkrachtig.', seconds: 30),
      ],
    ),
    Routine(
      id: 'warmup_snelheid',
      title: 'Warming-up voor snelheid',
      subtitle: 'Voor intervallen, tempo of een wedstrijd: loopscholing en versnellingen',
      icon: 'speed',
      category: RoutineCategory.warmup,
      rest: 10,
      note: 'Doe dit na 10 minuten rustig inlopen. Zoek een stuk rechte weg of een grasveld.',
      exercises: [
        Exercise('Skippings', 'Korte, snelle passen op de bal van je voet met je knieën een beetje omhoog. Armen actief mee.', seconds: 20),
        Exercise('Knieheffen vooruit', 'Loop vooruit en til bij elke stap je knie tot heuphoogte. Rechtop blijven, armen mee.', seconds: 20),
        Exercise('Hakken-billen vooruit', 'Loop vooruit en tik met je hakken tegen je billen, korte snelle passen.', seconds: 20),
        Exercise('Zijwaarts huppelen', 'Huppel zijwaarts met je armen mee omhoog. Halverwege omdraaien.', seconds: 20),
        Exercise('Kruispas', 'Loop zijwaarts en kruis je achterste been afwisselend voor en achter langs. Heupen draaien mee.', seconds: 20),
        Exercise('Huppelpas', 'Huppel vooruit met een hoge knie en een krachtige afzet, armen tegengesteld.', seconds: 20),
        Exercise('Versnelling 1', 'Loop 80 meter en bouw rustig op tot bijna je snelste tempo. Ontspannen schouders. Wandel terug.', seconds: 25),
        Exercise('Versnelling 2', 'Nog een keer: rustig opbouwen tot bijna je snelste tempo en ontspannen uitlopen.', seconds: 25),
        Exercise('Versnelling 3', 'De laatste: soepel en snel, maar niet voluit. Daarna ben je klaar voor de start.', seconds: 25),
      ],
    ),
    // ---------- Kracht ----------
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
      id: 'kracht_romp',
      title: 'Romp in 7 minuten',
      subtitle: 'Sterke buik en rug voor een stabiele houding als je moe wordt',
      icon: 'accessibility_new',
      rest: 10,
      exercises: [
        Exercise('Plank', 'Op je onderarmen en tenen, lijf recht van hoofd tot hielen. Buik aanspannen en rustig ademen.', seconds: 30),
        Exercise('Dead bug', 'Op je rug, armen omhoog, knieën boven je heupen. Strek langzaam tegenovergestelde arm en been, onderrug op de grond.'),
        Exercise('Zijplank', 'Op één onderarm en de zijkant van je voet, heupen omhoog. Knieën op de grond mag ook.', seconds: 25, perSide: true),
        Exercise('Vogel-hond', 'Op handen en knieën. Strek tegenovergestelde arm en been uit, rug stil als een tafel. Afwisselen.'),
        Exercise('Rugheffen', 'Op je buik, handen bij je oren. Til borst en armen een klein stukje op, kijk naar de grond. Rustig zakken.', seconds: 30),
        Exercise('Plank met schoudertik', 'In de plank op je handen: tik om de beurt je andere schouder aan zonder dat je heupen wiebelen.', seconds: 30),
      ],
    ),
    Routine(
      id: 'kracht_heup',
      title: 'Heup en bil',
      subtitle: 'Tegen knie- en IT-bandklachten: sterke bilspieren houden je knie recht',
      icon: 'directions_run',
      rest: 10,
      exercises: [
        Exercise('Schelpje', 'Op je zij, knieën gebogen en voeten tegen elkaar. Open je bovenste knie als een schelp, bekken stil. Rustig dicht.', seconds: 35, perSide: true),
        Exercise('Been zijwaarts heffen', 'Op je zij, onderste been gebogen. Til je bovenste been gestrekt schuin naar achter omhoog, tenen naar voren.', seconds: 30, perSide: true),
        Exercise('Brandkraantje', 'Op handen en knieën. Til één knie zijwaarts op tot heuphoogte, zonder je rug te draaien.', seconds: 30, perSide: true),
        Exercise('Eenbenige bilbrug', 'Op je rug, één voet op de grond en het andere been gestrekt. Duw je heupen omhoog, bekken recht.', seconds: 30, perSide: true),
        Exercise('Zijwaartse uitvalspas', 'Grote stap opzij, zak door die knie met je billen naar achter, ander been gestrekt. Terug en afwisselen.'),
        Exercise('Opstapje', 'Stap met één voet op een traptree of bankje en kom helemaal omhoog. Rustig terug. Knie boven je tenen.', seconds: 30, perSide: true),
      ],
    ),
    Routine(
      id: 'kracht_voet',
      title: 'Voet, kuit en scheen',
      subtitle: 'Voor sterke achillespezen en minder last van je schenen',
      icon: 'hiking',
      rest: 10,
      exercises: [
        Exercise('Langzaam kuitheffen op één been', 'Ga op twee voeten op je tenen staan, til één voet op en zak in drie tellen op het andere been. Houvast mag.', seconds: 40, perSide: true),
        Exercise('Kuitheffen met gebogen knie', 'Knieën licht gebogen, rustig op je tenen en weer zakken. Dit traint de diepe kuitspier.', seconds: 30),
        Exercise('Op je hakken lopen', 'Tenen omhoog en kleine stapjes op je hakken. Goed tegen scheenbeenklachten.', seconds: 30),
        Exercise('Op je tenen lopen', 'Hoog op je tenen kleine stapjes, hielen van de grond.', seconds: 30),
        Exercise('Korte voet', 'Trek je voetboog omhoog door je bal van je voet naar je hiel te trekken, zonder je tenen te krullen. Vasthouden en loslaten.', seconds: 30, perSide: true),
        Exercise('Balans op één been', 'Op één been staan, knie licht gebogen. Te makkelijk? Doe je ogen dicht.', seconds: 30, perSide: true),
      ],
    ),
    Routine(
      id: 'kracht_sprong',
      title: 'Sprongkracht',
      subtitle: 'Explosieve oefeningen voor een krachtigere afzet',
      icon: 'trending_up',
      rest: 30,
      note: 'Alleen als je blessurevrij bent en al een paar weken kracht doet. Land zacht en stil.',
      exercises: [
        Exercise('Enkelsprongen', 'Kleine, snelle sprongetjes op de bal van je voeten, knieën bijna gestrekt. Zoals touwtjespringen.', seconds: 25),
        Exercise('Squat-sprong', 'Zak in een squat en spring krachtig omhoog. Land zacht door je knieën en ga meteen weer zakken.', seconds: 25),
        Exercise('Schaatssprong', 'Spring zijwaarts van het ene been op het andere en land stil, als een schaatser.', seconds: 30),
        Exercise('Wisselsprong uitvalspas', 'In de uitvalspas, spring op en wissel in de lucht van been. Liever rustig dan slordig.', seconds: 25),
        Exercise('Hinkelen', 'Kleine sprongetjes vooruit op één been, zacht landen.', seconds: 15, perSide: true),
      ],
    ),
    // ---------- Mobiliteit ----------
    Routine(
      id: 'mob_heup',
      title: 'Heupen los',
      subtitle: 'Voor een langere, vrijere pas en minder stijve onderrug',
      icon: 'self_improvement',
      category: RoutineCategory.mobiliteit,
      rest: 5,
      exercises: [
        Exercise('Heupcirkels', 'Handen in je zij, grote rustige rondjes met je heupen. Halverwege de andere kant op.', seconds: 30),
        Exercise('90-90 zit', 'Zit met beide knieën 90 graden gebogen, één been voor en één opzij. Kom rechtop en kantel over je voorste been.', seconds: 40, perSide: true),
        Exercise('Grote uitvalspas met draai', 'Diepe uitvalspas, hand naast je voorste voet. Draai je andere arm open naar het plafond en kijk mee.', seconds: 30, perSide: true),
        Exercise('Diepe hurkzit', 'Zak zo diep als lukt met hielen op de grond. Ellebogen duwen je knieën rustig uit elkaar.', seconds: 40),
        Exercise('Kikker', 'Op handen en knieën, knieën wijd. Schuif je billen rustig naar achter tot je rek in je liezen voelt.', seconds: 40),
        Exercise('Voorkant heup', 'Halve knielzit, bil van je achterste been aanspannen en je heup rustig naar voren duwen.', seconds: 30, perSide: true),
      ],
    ),
    Routine(
      id: 'mob_enkel',
      title: 'Enkels en voeten',
      subtitle: 'Soepele enkels voor een betere afzet en landing',
      icon: 'airline_seat_legroom_extra',
      category: RoutineCategory.mobiliteit,
      rest: 5,
      exercises: [
        Exercise('Enkelrondjes', 'Op één been of zittend: grote, rustige rondjes met je voet, beide kanten op.', seconds: 20, perSide: true),
        Exercise('Knie naar de muur', 'Voet een handbreedte van de muur, duw je knie naar de muur zonder dat je hiel loskomt. Terug en herhalen.', seconds: 30, perSide: true),
        Exercise('Kuit tegen de muur', 'Handen tegen een muur, één been ver naar achter met de hak op de grond. Leun rustig naar voren.', seconds: 30, perSide: true),
        Exercise('Op je tenen zitten', 'Kniel met je tenen omgekruld onder je en zit rustig op je hielen. Te veel? Handen op de grond.', seconds: 30),
        Exercise('Voetzool rollen', 'Rol je voetzool rustig over een bal of flesje, van hiel tot tenen.', seconds: 30, perSide: true),
      ],
    ),
    Routine(
      id: 'mob_rug',
      title: 'Rug en schouders',
      subtitle: 'Voor een open borst en rechte houding, ook na een dag zitten',
      icon: 'airline_seat_recline_normal',
      category: RoutineCategory.mobiliteit,
      rest: 5,
      exercises: [
        Exercise('Kat en koe', 'Op handen en knieën. Maak je rug rond en dan hol, rustig mee met je adem.', seconds: 40),
        Exercise('Draad door de naald', 'Op handen en knieën, schuif één arm onder je door en laat je schouder zakken. Daarna open draaien.', seconds: 30, perSide: true),
        Exercise('Open boek', 'Op je zij, knieën gebogen, armen voor je. Draai je bovenste arm in een boog open naar de andere kant.', seconds: 30, perSide: true),
        Exercise('Armcirkels', 'Rechtop, armen gestrekt. Draai rustige grote cirkels, halverwege de andere kant op.', seconds: 30),
        Exercise('Kindhouding', 'Zit op je hielen, buig voorover en strek je armen ver naar voren. Adem rustig in je rug.', seconds: 40),
      ],
    ),
    Routine(
      id: 'yoga',
      title: 'Yoga voor lopers',
      subtitle: 'Tien minuten rustig bewegen en rekken op een rustdag',
      icon: 'spa',
      category: RoutineCategory.mobiliteit,
      rest: 5,
      exercises: [
        Exercise('Neerwaartse hond', 'Handen en voeten op de grond, billen hoog. Trap om de beurt je hakken naar de grond.', seconds: 40),
        Exercise('Lage uitvalspas', 'Achterste knie op de grond, heupen zakken naar voren, armen omhoog.', seconds: 40, perSide: true),
        Exercise('Duif', 'Voorste been gebogen voor je op de grond, achterste been gestrekt naar achter. Zak rustig voorover.', seconds: 45, perSide: true),
        Exercise('Staande vooroverbuiging', 'Voeten op heupbreedte, knieën zacht. Laat je bovenlijf hangen en schud je hoofd los.', seconds: 40),
        Exercise('Liggende draai', 'Op je rug, trek één knie over je lijf naar de andere kant. Armen wijd, schouders op de grond.', seconds: 40, perSide: true),
        Exercise('Kindhouding', 'Zit op je hielen, armen ver naar voren, voorhoofd op de grond. Rustig ademen.', seconds: 45),
      ],
    ),
    // ---------- Cooling-down ----------
    Routine(
      id: 'cooldown',
      title: 'Rekken na je run',
      subtitle: 'Rustig rekken voor kuiten, benen en heupen',
      icon: 'self_improvement',
      category: RoutineCategory.cooldown,
      rest: 5,
      exercises: [
        Exercise('Kuit', 'Handen tegen een muur, één been ver naar achter met de hak op de grond. Leun rustig naar voren.', seconds: 30, perSide: true),
        Exercise('Achterkant bovenbeen', 'Hak op een lage verhoging, been gestrekt, en kantel vanuit je heup naar voren tot je rek voelt.', seconds: 30, perSide: true),
        Exercise('Voorkant heup', 'Halve knielzit, duw je heup rustig naar voren tot je rek voelt aan de voorkant van je achterste been.', seconds: 30, perSide: true),
        Exercise('Bil (figuur 4)', 'Op je rug, enkel op de andere knie en trek dat been rustig naar je toe.', seconds: 30, perSide: true),
        Exercise('Onderrug', 'Op je rug, knieën naar je borst en zacht heen en weer wiegen.', seconds: 30),
      ],
    ),
    Routine(
      id: 'cooldown_staand',
      title: 'Cooling-down onderweg',
      subtitle: 'Uitwandelen en staand rekken, zonder op de grond te gaan',
      icon: 'directions_walk',
      category: RoutineCategory.cooldown,
      rest: 5,
      exercises: [
        Exercise('Uitwandelen', 'Wandel rustig verder en laat je ademhaling tot rust komen. Schouders los.', seconds: 120),
        Exercise('Rustig ademen', 'Adem vier tellen in door je neus en zes tellen uit door je mond.', seconds: 45),
        Exercise('Kuit', 'Handen tegen een muur of paal, één been ver naar achter met de hak op de grond. Leun rustig naar voren.', seconds: 30, perSide: true),
        Exercise('Voorkant bovenbeen', 'Pak je enkel en trek je hak naar je bil, knieën naast elkaar. Houvast mag.', seconds: 30, perSide: true),
        Exercise('Achterkant bovenbeen staand', 'Hak voor je op de grond, been gestrekt, tenen omhoog. Kantel met rechte rug naar voren.', seconds: 30, perSide: true),
      ],
    ),
    Routine(
      id: 'cooldown_herstel',
      title: 'Herstel na een lange run',
      subtitle: 'Liggend ontspannen en rekken, ook fijn voor het slapen',
      icon: 'bedtime',
      category: RoutineCategory.cooldown,
      rest: 5,
      exercises: [
        Exercise('Benen tegen de muur', 'Op je rug met je billen dicht bij de muur en je benen omhoog ertegenaan. Laat alles zakken.', seconds: 90),
        Exercise('Liggende achterkant bovenbeen', 'Op je rug, één been omhoog, handen achter je bovenbeen. Rustig naar je toe trekken.', seconds: 40, perSide: true),
        Exercise('Bil (figuur 4)', 'Op je rug, enkel op de andere knie en trek dat been rustig naar je toe.', seconds: 40, perSide: true),
        Exercise('Liggende draai', 'Op je rug, trek één knie over je lijf naar de andere kant. Schouders op de grond.', seconds: 40, perSide: true),
        Exercise('Kindhouding', 'Zit op je hielen, armen naar voren, voorhoofd op de grond.', seconds: 45),
        Exercise('Ademhaling', 'Op je rug, hand op je buik. Adem vier tellen in en zes tellen uit. Laat je lijf zwaar worden.', seconds: 60),
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

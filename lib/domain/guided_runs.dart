/// Begeleide runs: de stem van de coach praat je door een run heen (zoals de Guided Runs van Nike Run Club).
/// Eigen RunWise-teksten; de app spreekt ze uit op het juiste moment (op bewegende tijd).
class GuidedCue {
  const GuidedCue(this.atMinute, this.text);
  final double atMinute;
  final String text;
}

class GuidedRun {
  const GuidedRun({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.minutes,
    required this.cues,
  });

  final String id;
  final String title;
  final String subtitle;
  final int minutes;
  final List<GuidedCue> cues;

  static const all = <GuidedRun>[
    GuidedRun(
      id: 'eerste',
      title: 'Je eerste 20 minuten',
      subtitle: 'Rustig beginnen, zonder druk',
      minutes: 20,
      cues: [
        GuidedCue(0, 'Welkom. We lopen twintig minuten, heel rustig. Je mag praten, en wandelen mag ook. Het gaat erom dat je onderweg bent.'),
        GuidedCue(2, 'Kijk eens hoe je ademt. Gaat het zwaar? Dan iets langzamer. Langzaam is hier precies goed.'),
        GuidedCue(5, 'Vijf minuten. Ontspan je schouders en laat je armen losjes meebewegen.'),
        GuidedCue(8, 'Je lichaam is nu opgewarmd. Veel lopers vinden dit het lastigste stuk. Gewoon doorgaan, het wordt makkelijker.'),
        GuidedCue(10, 'Halverwege. Tien minuten gedaan, nog tien te gaan. Goed bezig.'),
        GuidedCue(14, 'Zet je voeten zacht neer, onder je lichaam. Kleine passen kosten minder energie.'),
        GuidedCue(17, 'Nog drie minuten. Kijk even om je heen: je loopt gewoon hard.'),
        GuidedCue(19, 'Laatste minuut. Wil je, versnel dan een klein beetje. Hoeft niet.'),
        GuidedCue(20, 'Klaar! Twintig minuten. Wandel nog even uit en drink wat. Deze run telt.'),
      ],
    ),
    GuidedRun(
      id: 'herstel',
      title: 'Herstelrun',
      subtitle: '30 minuten echt rustig, na een zware dag',
      minutes: 30,
      cues: [
        GuidedCue(0, 'Dit is een herstelrun. Het doel is niet snel lopen, maar je benen los maken. Kies een tempo waarbij je makkelijk kunt praten.'),
        GuidedCue(4, 'Voelt het te makkelijk? Mooi. Zo hoort het bij herstel.'),
        GuidedCue(10, 'Tien minuten. Let op je adem: rustig door je neus en mond, zonder te hijgen.'),
        GuidedCue(15, 'Halverwege. Rustige runs zijn de basis van je conditie. De meeste goede lopers doen het grootste deel van hun training zo.'),
        GuidedCue(22, 'Ontspan je gezicht, je kaak en je handen. Spanning kost energie.'),
        GuidedCue(27, 'Nog drie minuten. Blijf rustig, ook als je je goed voelt.'),
        GuidedCue(30, 'Klaar. Je benen zijn los en je hebt je lichaam geholpen herstellen. Morgen ben je frisser.'),
      ],
    ),
    GuidedRun(
      id: 'fartlek',
      title: 'Fartlek met de coach',
      subtitle: '35 minuten met korte versnellingen op gevoel',
      minutes: 35,
      cues: [
        GuidedCue(0, 'Fartlek betekent spelen met snelheid. Eerst tien minuten rustig inlopen. Ik zeg wanneer je mag versnellen.'),
        GuidedCue(10, 'Klaar? Versnel nu, één minuut, stevig maar niet voluit.'),
        GuidedCue(11, 'En rustig. Twee minuten herstellen.'),
        GuidedCue(13, 'Versnel weer. Eén minuut. Korte passen, armen mee.'),
        GuidedCue(14, 'Rustig. Laat je adem zakken.'),
        GuidedCue(16, 'Nu dertig seconden flink. Pak een lantaarnpaal of boom als doel.'),
        GuidedCue(16.5, 'Rustig. Mooi.'),
        GuidedCue(18, 'Laatste blok: twee minuten op het tempo van een wedstrijd van tien kilometer.'),
        GuidedCue(20, 'Klaar met de versnellingen. Nu rustig uitlopen.'),
        GuidedCue(27, 'Je doet het goed. Snelheid trainen maakt je rustige runs straks makkelijker.'),
        GuidedCue(33, 'Nog twee minuten. Helemaal rustig.'),
        GuidedCue(35, 'Klaar! Een mooie fartlek. Rek je kuiten en drink wat.'),
      ],
    ),
    GuidedRun(
      id: 'lang',
      title: 'Lange duurloop',
      subtitle: '60 minuten met tips voor tempo, drinken en je hoofd',
      minutes: 60,
      cues: [
        GuidedCue(0, 'Een uur lopen. Het geheim van een lange duurloop: begin langzamer dan je denkt. Je wilt aan het eind nog iets over hebben.'),
        GuidedCue(8, 'Je bent op gang. Zoek een tempo dat je een uur kunt volhouden en hou dat vast.'),
        GuidedCue(15, 'Een kwartier. Check je houding: rechtop, blik vooruit, schouders laag.'),
        GuidedCue(25, 'Heb je drinken bij je? Neem een paar slokken, ook als je nog geen dorst hebt.'),
        GuidedCue(30, 'Halverwege. Verdeel de rest in kleine stukjes: alleen nog maar het volgende kwartier.'),
        GuidedCue(40, 'Rond nu wordt het vaak zwaarder. Dat is normaal. Adem rustig uit, en focus op je passen.'),
        GuidedCue(45, 'Nog een kwartier. Bij langere runs: dit is een goed moment voor een gel of iets zoets.'),
        GuidedCue(52, 'Je hebt het meeste werk gedaan. Blijf ontspannen, ook als je benen moe zijn.'),
        GuidedCue(57, 'Nog drie minuten. Je mag een klein beetje versnellen als het goed voelt.'),
        GuidedCue(60, 'Een uur! Dit is de run die je sterk maakt voor lange afstanden. Wandel uit, eet en drink wat.'),
      ],
    ),
    GuidedRun(
      id: 'adem',
      title: 'Ademen en ontspannen',
      subtitle: '25 minuten lopen met aandacht',
      minutes: 25,
      cues: [
        GuidedCue(0, 'Deze run gaat over aandacht. Laat je horloge even voor wat het is en loop rustig.'),
        GuidedCue(3, 'Tel je passen mee met je adem: drie passen in, drie passen uit. Kijk of dat vanzelf gaat.'),
        GuidedCue(7, 'Wat hoor je om je heen? Vogels, verkeer, je eigen voeten. Gewoon opmerken.'),
        GuidedCue(12, 'Halverwege. Merk waar je spanning voelt, en laat die bij je volgende uitademing los.'),
        GuidedCue(17, 'Probeer nu twee passen in, twee passen uit. Iets steviger, maar nog ontspannen.'),
        GuidedCue(21, 'Terug naar drie in, drie uit. Rustig.'),
        GuidedCue(25, 'Klaar. Neem even de tijd om stil te staan en een paar keer diep adem te halen. Mooi gedaan.'),
      ],
    ),
  ];
}

/// Houdt bij welke tekst er nog moet komen.
class GuidedPlayer {
  GuidedPlayer(this.run);
  final GuidedRun run;
  int _next = 0;

  bool get finished => _next >= run.cues.length;

  /// Tekst die nu uitgesproken moet worden (of null). Bij een sprong in de tijd alleen de laatste.
  String? update(double movingSeconds) {
    String? say;
    while (_next < run.cues.length && movingSeconds >= run.cues[_next].atMinute * 60) {
      say = run.cues[_next].text;
      _next++;
    }
    return say;
  }
}

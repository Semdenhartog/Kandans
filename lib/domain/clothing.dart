import '../data/models/models.dart';
import 'start_time_scoring.dart';

/// Hoe snel je het koud of warm hebt (Ik → Kledingadvies). Schuift het advies een paar graden op.
enum ClothingFeel {
  cold('Ik heb het snel koud', 'Advies een laagje warmer', -3),
  normal('Normaal', 'Het standaard advies', 0),
  warm('Ik heb het snel warm', 'Advies een laagje luchtiger', 3);

  const ClothingFeel(this.label, this.explanation, this.bias);
  final String label;
  final String explanation;

  /// Graden die bij de "looptemperatuur" opgeteld worden.
  final int bias;
}

/// Kledingadvies voor één run.
class ClothingAdvice {
  const ClothingAdvice({required this.summary, required this.items, required this.extras});

  /// Korte samenvatting, bijv. "Korte broek + shirt met lange mouwen".
  final String summary;

  /// Kleding van boven naar beneden.
  final List<String> items;

  /// Extra tips (regen, wind, zon, donker, drinken).
  final List<String> extras;
}

/// Vuistregel voor hardlopers: kleed je alsof het ongeveer 10 graden warmer is,
/// want je warmt onderweg op. Bij tempo nog iets meer, bij herstel iets minder.
double runningTemperature(double feelsLike, TrainingType type) => feelsLike +
    switch (type) {
      TrainingType.quality => 11,
      TrainingType.long => 9,
      TrainingType.easy => 9,
      TrainingType.recovery => 7,
    };

ClothingAdvice clothingFor(HourWeather w, TrainingType type, {int durationMinutes = 45, ClothingFeel feel = ClothingFeel.normal}) {
  final feels = w.feelsLike ?? w.temperature;
  final t = runningTemperature(feels, type) + feel.bias;
  final items = <String>[];
  final String summary;

  if (t < 5) {
    items.addAll(['Muts of oorwarmer', 'Handschoenen', 'Thermoshirt met lange mouwen', 'Winddicht jack', 'Lange (thermo)tight']);
    summary = 'Winterkleding: thermo, jack, muts en handschoenen';
  } else if (t < 10) {
    items.addAll(['Dunne handschoenen', 'Shirt met lange mouwen', 'Dun jack', 'Lange tight']);
    summary = 'Lange tight, lange mouwen en een dun jack';
  } else if (t < 15) {
    items.addAll(['Shirt met lange mouwen', 'Lange of 3/4 tight']);
    summary = 'Lange mouwen met een lange of 3/4 tight';
  } else if (t < 20) {
    items.addAll(['Shirt met korte of lange mouwen', 'Korte broek']);
    summary = 'Korte broek met korte of lange mouwen';
  } else if (t < 25) {
    items.addAll(['T-shirt', 'Korte broek']);
    summary = 'Korte broek en T-shirt';
  } else {
    items.addAll(['Singlet of luchtig shirt', 'Korte broek', 'Pet']);
    summary = 'Zo luchtig mogelijk: singlet en korte broek';
  }

  final extras = <String>[];
  final rainProb = w.precipitationProbability ?? 0;
  final rain = w.precipitation ?? 0;
  if (rain >= 0.3 || rainProb >= 50) {
    extras.add(feels < 14 ? 'Regenjack: grote kans op nat worden, en nat is koud' : 'Dun regenjack, of accepteer nat worden: het is warm genoeg');
  }
  if (w.windSpeed >= 25 && t < 20 && !items.any((i) => i.contains('jack'))) {
    extras.add('Winddicht jack tegen de harde wind (${w.windSpeed.round()} km/u)');
  }
  if ((w.uvIndex ?? 0) >= 5 && w.isDay) extras.add('Pet en zonnebrand (UV ${w.uvIndex!.round()})');
  if (!w.isDay) extras.add('Reflecterende kleding en een lampje: het is donker');
  if (w.temperature <= 1) extras.add('Kans op gladheid: kies schoenen met grip of een veilige route');
  // Drinken: hoeveel, afhankelijk van warmte en duur.
  if (feels >= 22 && durationMinutes >= 45) {
    extras.add('Drink vooraf een glas water en neem 400–700 ml per uur mee: het is warm');
  } else if (durationMinutes >= 75 && feels >= 15) {
    extras.add('Neem drinken mee (ongeveer 400–600 ml per uur): je bent lang onderweg');
  } else if (durationMinutes >= 90) {
    extras.add('Neem iets te drinken mee voor onderweg: je bent lang weg');
  }

  return ClothingAdvice(summary: summary, items: items, extras: extras);
}

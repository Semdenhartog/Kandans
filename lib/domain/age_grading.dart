import 'dart:math' as math;

// Leeftijdsniveau ("age grading"): je tijd vergeleken met de wereldtop voor jouw leeftijd en geslacht.
// Benadering van de WMA-normen (World Masters Athletics, wegatletiek): wereldrecord-niveau per afstand
// en een leeftijdsfactor. Geen officiële tabel; afwijking ±1 procentpunt.

enum Sex { male, female }

/// Open wereldniveau (seconden) per afstand (meter).
const _standards = <Sex, Map<int, double>>{
  Sex.male: {5000: 769, 10000: 1584, 15000: 2478, 21098: 3451, 42195: 7235},
  Sex.female: {5000: 846, 10000: 1757, 15000: 2660, 21098: 3772, 42195: 8044},
};

/// Leeftijdsfactor (1 = beste leeftijd). Tussen de punten lineair.
const _factors = <Sex, List<(int, double)>>{
  Sex.male: [(10, 0.78), (12, 0.85), (14, 0.90), (16, 0.95), (18, 0.98), (20, 1.0), (30, 1.0), (35, 0.982), (40, 0.948), (45, 0.913), (50, 0.878), (55, 0.843), (60, 0.808), (65, 0.773), (70, 0.737), (75, 0.698), (80, 0.652), (85, 0.598), (90, 0.535), (100, 0.38)],
  Sex.female: [(10, 0.78), (12, 0.85), (14, 0.90), (16, 0.95), (18, 0.98), (20, 1.0), (30, 1.0), (35, 0.980), (40, 0.944), (45, 0.905), (50, 0.866), (55, 0.828), (60, 0.789), (65, 0.749), (70, 0.707), (75, 0.661), (80, 0.608), (85, 0.548), (90, 0.481), (100, 0.33)],
};

double ageFactor(Sex sex, int age) {
  final t = _factors[sex]!;
  if (age <= t.first.$1) return t.first.$2;
  if (age >= t.last.$1) return t.last.$2;
  for (var i = 1; i < t.length; i++) {
    final (a1, f1) = t[i - 1];
    final (a2, f2) = t[i];
    if (age <= a2) return f1 + (f2 - f1) * (age - a1) / (a2 - a1);
  }
  return t.last.$2;
}

/// Wereldniveau op [meters] (tussen de standaardafstanden: Riegel-formule vanaf de dichtstbijzijnde).
double? openStandard(Sex sex, double meters) {
  if (meters < 3000 || meters > 43000) return null;
  final s = _standards[sex]!;
  final nearest = s.keys.reduce((a, b) => (a - meters).abs() <= (b - meters).abs() ? a : b);
  final base = s[nearest]!;
  return base * math.pow(meters / nearest, 1.06).toDouble();
}

/// Leeftijdsniveau in procent (100 = wereldrecord-niveau voor je leeftijd). Null als de afstand niet past.
double? ageGradePercent({required Sex sex, required int age, required double meters, required double seconds}) {
  final open = openStandard(sex, meters);
  if (open == null || seconds <= 0 || age < 10 || age > 100) return null;
  final ageStandard = open / ageFactor(sex, age);
  return ageStandard / seconds * 100;
}

/// Uitleg bij een percentage.
String ageGradeLevel(double pct) => pct >= 90
    ? 'Wereldklasse'
    : pct >= 80
        ? 'Nationaal niveau'
        : pct >= 70
            ? 'Regionaal niveau'
            : pct >= 60
                ? 'Lokaal sterk'
                : pct >= 50
                    ? 'Goede recreant'
                    : 'Recreant';

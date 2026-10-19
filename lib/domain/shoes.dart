import '../data/models/models.dart';

/// Hoeveel km er op een schoen zit: wat er al op zat, plus de runs die je erop liep.
/// Runs zonder schoen tellen mee voor je standaardschoen (vanaf het moment dat je hem toevoegde).
double shoeKm(Shoe shoe, List<Activity> runs) {
  var m = 0.0;
  for (final a in runs) {
    if (a.shoeId == shoe.id) {
      m += a.distanceMeters;
    } else if (a.shoeId == null && shoe.isDefault && !shoe.retired && !a.startedAt.isBefore(shoe.createdAt)) {
      m += a.distanceMeters;
    }
  }
  return shoe.startKm + m / 1000;
}

/// Je standaardschoen (null als je er geen hebt).
Shoe? defaultShoe(List<Shoe> shoes) {
  for (final s in shoes) {
    if (s.isDefault && !s.retired) return s;
  }
  return null;
}

/// Is het tijd voor nieuwe schoenen? (vanaf 90% van je grens)
bool shoeWornOut(Shoe shoe, List<Activity> runs) => shoeKm(shoe, runs) >= shoe.limitKm * 0.9;

/// Welke schoen hoort bij deze run.
Shoe? shoeFor(Activity a, List<Shoe> shoes) {
  if (a.shoeId != null) {
    for (final s in shoes) {
      if (s.id == a.shoeId) return s;
    }
    return null;
  }
  final d = defaultShoe(shoes);
  return d != null && !a.startedAt.isBefore(d.createdAt) ? d : null;
}

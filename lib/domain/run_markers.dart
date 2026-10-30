import 'geo.dart';

// Markeringen tijdens het lopen (idee uit OpenTracks): één tik zet een punt op je run,
// eventueel met een foto. Bewaard in het verloop als `marks`.

enum MarkerKind { view, water, toilet, badPath, danger, dog, note }

extension MarkerKindText on MarkerKind {
  String get label => switch (this) {
        MarkerKind.view => 'Mooi uitzicht',
        MarkerKind.water => 'Water',
        MarkerKind.toilet => 'Toilet',
        MarkerKind.badPath => 'Slecht pad',
        MarkerKind.danger => 'Gevaarlijk',
        MarkerKind.dog => 'Loslopende hond',
        MarkerKind.note => 'Markering',
      };

  static MarkerKind parse(Object? v) =>
      MarkerKind.values.firstWhere((k) => k.name == v, orElse: () => MarkerKind.note);
}

class RunMarker {
  const RunMarker({
    required this.seconds,
    required this.meters,
    required this.point,
    this.kind = MarkerKind.note,
    this.note,
    this.photo,
    this.localPhoto,
  });

  /// Bewegende tijd en afstand op het moment van markeren.
  final double seconds;
  final double meters;
  final LatLng point;
  final MarkerKind kind;
  final String? note;

  /// Pad van de foto in de opslag (na uploaden).
  final String? photo;

  /// Foto op de telefoon (nog niet geüpload). Gaat niet mee naar de server.
  final String? localPhoto;

  String get title => (note != null && note!.trim().isNotEmpty) ? note!.trim() : kind.label;

  RunMarker copyWith({String? photo, String? localPhoto, bool clearLocal = false}) => RunMarker(
        seconds: seconds,
        meters: meters,
        point: point,
        kind: kind,
        note: note,
        photo: photo ?? this.photo,
        localPhoto: clearLocal ? null : (localPhoto ?? this.localPhoto),
      );

  /// Voor het verloop op de server (zonder lokaal pad).
  Map<String, dynamic> toJson({bool includeLocal = false}) => {
        't': double.parse(seconds.toStringAsFixed(1)),
        'd': double.parse(meters.toStringAsFixed(1)),
        'll': [double.parse(point.lat.toStringAsFixed(6)), double.parse(point.lon.toStringAsFixed(6))],
        'k': kind.name,
        if (note != null && note!.trim().isNotEmpty) 'n': note!.trim(),
        if (photo != null) 'p': photo,
        if (includeLocal && localPhoto != null) 'lp': localPhoto,
      };

  static RunMarker? fromJson(Object? j) {
    if (j is! Map) return null;
    final ll = j['ll'];
    if (ll is! List || ll.length < 2) return null;
    return RunMarker(
      seconds: (j['t'] as num?)?.toDouble() ?? 0,
      meters: (j['d'] as num?)?.toDouble() ?? 0,
      point: LatLng((ll[0] as num).toDouble(), (ll[1] as num).toDouble()),
      kind: MarkerKindText.parse(j['k']),
      note: j['n'] as String?,
      photo: j['p'] as String?,
      localPhoto: j['lp'] as String?,
    );
  }
}

/// Markeringen uit het verloop van een run.
List<RunMarker> markersOf(Map<String, dynamic>? streams) {
  final v = streams?['marks'];
  if (v is! List) return const [];
  return [
    for (final m in v)
      if (RunMarker.fromJson(m) case final r?) r,
  ];
}

/// Na bijsnijden: alleen markeringen binnen het nieuwe stuk, met verschoven tijd en afstand.
List<Map<String, dynamic>> shiftMarkers(Object? marks, {required double fromT, required double fromD, required double toD}) {
  if (marks is! List) return const [];
  return [
    for (final m in marks)
      if (RunMarker.fromJson(m) case final r? when r.meters >= fromD && r.meters <= toD)
        {
          ...(m as Map).cast<String, dynamic>(),
          't': double.parse((r.seconds - fromT).clamp(0, double.infinity).toStringAsFixed(1)),
          'd': double.parse((r.meters - fromD).toStringAsFixed(1)),
        },
  ];
}

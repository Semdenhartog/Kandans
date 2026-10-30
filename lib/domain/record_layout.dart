import 'dart:convert';

// Opnamescherm zelf indelen (idee uit OpenTracks: "custom recording layout").
// Eén hoofdcijfer (groot, in de ring of los) en tot 6 kleinere cijfers in 2 of 3 kolommen.

/// Wat je tijdens het lopen kunt zien.
enum RecField { distance, time, currentPace, averagePace, kmPace, heartRate, cadence, elevationGain, clock, lastKm }

extension RecFieldText on RecField {
  String get label => switch (this) {
        RecField.distance => 'Afstand',
        RecField.time => 'Tijd',
        RecField.currentPace => 'Tempo nu',
        RecField.averagePace => 'Gemiddeld',
        RecField.kmPace => 'Tempo deze km',
        RecField.heartRate => 'Hartslag',
        RecField.cadence => 'Cadans',
        RecField.elevationGain => 'Hoogtemeters',
        RecField.clock => 'Klok',
        RecField.lastKm => 'Vorige km',
      };

  /// Eenheid onder het grote cijfer.
  String get unit => switch (this) {
        RecField.distance => 'kilometer',
        RecField.time => 'tijd',
        RecField.currentPace || RecField.averagePace || RecField.kmPace || RecField.lastKm => 'min/km',
        RecField.heartRate => 'slagen/min',
        RecField.cadence => 'stappen/min',
        RecField.elevationGain => 'meter omhoog',
        RecField.clock => 'klok',
      };
}

/// Ring = het hoofdcijfer in de km-ring (zoals altijd). Groot = twee enorme cijfers, verder niets.
enum RecStyle { ring, big }

class RecordLayout {
  const RecordLayout({
    required this.name,
    this.style = RecStyle.ring,
    this.main = RecField.distance,
    this.fields = const [RecField.time, RecField.currentPace, RecField.averagePace],
    this.columns = 3,
  });

  final String name;
  final RecStyle style;
  final RecField main;

  /// Kleine cijfers onder het hoofdcijfer (max. 6). Bij [RecStyle.big] alleen het eerste, ook groot.
  final List<RecField> fields;
  final int columns;

  static const maxFields = 6;

  RecordLayout copyWith({String? name, RecStyle? style, RecField? main, List<RecField>? fields, int? columns}) => RecordLayout(
        name: name ?? this.name,
        style: style ?? this.style,
        main: main ?? this.main,
        fields: (fields ?? this.fields).take(maxFields).toList(),
        columns: (columns ?? this.columns).clamp(2, 3),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'style': style.name,
        'main': main.name,
        'fields': [for (final f in fields) f.name],
        'cols': columns,
      };

  static RecordLayout? fromJson(Object? j) {
    if (j is! Map) return null;
    RecField? f(Object? v) => RecField.values.where((x) => x.name == v).firstOrNull;
    final name = j['name'];
    if (name is! String || name.trim().isEmpty) return null;
    return RecordLayout(
      name: name,
      style: RecStyle.values.where((x) => x.name == j['style']).firstOrNull ?? RecStyle.ring,
      main: f(j['main']) ?? RecField.distance,
      fields: [
        for (final x in (j['fields'] as List? ?? const []))
          if (f(x) case final v?) v,
      ].take(maxFields).toList(),
      columns: ((j['cols'] as num?)?.toInt() ?? 3).clamp(2, 3),
    );
  }

  /// Kant-en-klare indelingen. De eerste is hoe het opnamescherm altijd was.
  static const presets = <RecordLayout>[
    RecordLayout(name: 'Standaard'),
    RecordLayout(name: 'Minimaal', style: RecStyle.big, main: RecField.time, fields: [RecField.distance]),
    RecordLayout(
      name: 'Hartslag',
      main: RecField.heartRate,
      fields: [RecField.distance, RecField.time, RecField.currentPace],
    ),
    RecordLayout(
      name: 'Compleet',
      fields: [RecField.time, RecField.currentPace, RecField.averagePace, RecField.heartRate, RecField.cadence, RecField.elevationGain],
    ),
  ];

  static String encodeAll(List<RecordLayout> list) => jsonEncode([for (final l in list) l.toJson()]);

  /// Leest bewaarde indelingen; leeg of kapot = de kant-en-klare.
  static List<RecordLayout> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return List.of(presets);
    try {
      final list = [
        for (final x in jsonDecode(raw) as List)
          if (RecordLayout.fromJson(x) case final l?) l,
      ];
      return list.isEmpty ? List.of(presets) : list;
    } catch (_) {
      return List.of(presets);
    }
  }
}

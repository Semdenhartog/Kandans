import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'run_file_import.dart';

/// Eén activiteit uit activities.csv van een Strava-archief.
class StravaArchiveItem {
  StravaArchiveItem({required this.id, required this.name, required this.type, required this.file});
  final String id;
  final String name;
  final String type;

  /// Pad in de zip, bijv. "activities/1234567890.fit.gz". Leeg als er geen bestand bij zit.
  final String file;

  bool get isRun => isStravaRunType(type);
  bool get hasFile => file.isNotEmpty;
}

/// Hardlopen in de talen waarin Strava het archief schrijft (Run, Trail Run, Virtual Run, Hardlopen, Lauf, …).
bool isStravaRunType(String type) {
  final t = type.toLowerCase();
  if (t.contains('wheelchair') || t.contains('rolstoel') || t.contains('langlauf') || t.contains('ski')) return false;
  const words = ['run', 'hardlo', 'lauf', 'course', 'carrera', 'corsa', 'corrida', 'löp', 'trail'];
  return words.any(t.contains);
}

/// CSV lezen met aanhalingstekens, komma's en regeleinden binnen velden.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;
  if (text.startsWith('﻿')) i = 1;
  while (i < text.length) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
  }
  return rows;
}

/// Leest activities.csv. De kolomnamen verschillen per taal, dus: id = 1e kolom, naam = 3e, soort = 4e,
/// en het bestand is de kolom waarvan de waarde met "activities/" begint.
List<StravaArchiveItem> parseStravaActivitiesCsv(String text) {
  final rows = parseCsv(text);
  if (rows.length < 2) return const [];
  final out = <StravaArchiveItem>[];
  for (final r in rows.skip(1)) {
    if (r.length < 4) continue;
    final id = r[0].trim();
    if (id.isEmpty || int.tryParse(id) == null) continue;
    final file = r.firstWhere((v) => v.trim().toLowerCase().startsWith('activities/'), orElse: () => '').trim();
    out.add(StravaArchiveItem(id: id, name: r[2].trim(), type: r[3].trim(), file: file));
  }
  return out;
}

/// Maakt van een bestand uit het archief een run (gpx, tcx of fit, eventueel ingepakt als .gz).
ImportedRun parseStravaArchiveFile(String path, Uint8List bytes, {String? name}) {
  var lower = path.toLowerCase();
  var data = bytes;
  if (lower.endsWith('.gz')) {
    try {
      data = Uint8List.fromList(GZipCodec().decode(bytes));
    } catch (_) {
      throw RunFileException('Dit bestand is beschadigd.');
    }
    lower = lower.substring(0, lower.length - 3);
  }
  if (lower.endsWith('.fit')) return parseFitRun(data, name: name);
  if (lower.endsWith('.gpx') || lower.endsWith('.tcx')) {
    final run = parseRunFile(utf8.decode(data, allowMalformed: true));
    if (name == null || name.isEmpty) return run;
    return ImportedRun(
      start: run.start,
      distanceMeters: run.distanceMeters,
      movingSeconds: run.movingSeconds,
      track: run.track,
      streams: run.streams,
      averageHeartRate: run.averageHeartRate,
      elevationGain: run.elevationGain,
      name: name,
    );
  }
  throw RunFileException('Onbekend bestandstype.');
}

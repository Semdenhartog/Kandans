import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/run_recorder.dart';

/// Bewaart een lopende opname op de telefoon, zodat je run niet verloren gaat als
/// Android de app afsluit of je telefoon uitvalt.
class RecordingStore {
  RecordingStore._();

  static Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/active_run.json');

  static Future<void> save(RunRecording r) async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(r.toSnapshot()), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// Een onderbroken run (of null). Runs ouder dan 2 dagen tellen niet meer.
  static Future<RunRecording?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      if (DateTime.now().difference(await f.lastModified()) > const Duration(days: 2)) {
        await f.delete();
        return null;
      }
      final r = RunRecording.fromSnapshot(jsonDecode(await f.readAsString()));
      if (r == null || (r.distance < 100 && r.movingSeconds < 60)) {
        await f.delete();
        return null;
      }
      return r;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

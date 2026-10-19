import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/records.dart';

/// Je records op basis van al je runs.
final recordsProvider = Provider<Records>((ref) {
  final list = ref.watch(activitiesProvider).value ?? const <Activity>[];
  return computeRecords(list);
});

/// Eén run uit de lijst (null als hij niet (meer) bestaat).
final activityProvider = Provider.family<Activity?, String>((ref, id) {
  final list = ref.watch(activitiesProvider).value ?? const <Activity>[];
  for (final a in list) {
    if (a.id == id) return a;
  }
  return null;
});

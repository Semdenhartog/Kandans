import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';

/// Routes die net "verwijderd" zijn, maar nog 5 seconden terug kunnen. De routelijst verbergt ze.
final hiddenRoutes = ValueNotifier<Set<String>>(const {});

/// Verwijdert een route met 5 seconden om het ongedaan te maken (geen pop-up vooraf).
Future<void> deleteRouteWithUndo(BuildContext context, RunRoute r) async {
  final id = r.id;
  if (id == null) return;
  final messenger = ScaffoldMessenger.of(context);
  // Het detailscherm verdwijnt meteen; daarom werken we hierna met de app-brede container.
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(repositoryProvider);
  hiddenRoutes.value = {...hiddenRoutes.value, id};
  context.go('/routes');
  messenger.hideCurrentSnackBar();
  var undone = false;
  final bar = messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 5),
    content: Text('"${r.name}" verwijderd'),
    action: SnackBarAction(label: 'Ongedaan maken', onPressed: () => undone = true),
  ));
  await bar.closed;
  try {
    if (!undone) {
      await repo.deleteRoute(id);
      container.invalidate(routesProvider);
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  } finally {
    hiddenRoutes.value = {...hiddenRoutes.value}..remove(id);
  }
}

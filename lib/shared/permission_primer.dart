import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/services/location_service.dart';

/// Legt uit waarom RunWise je locatie wil, vóórdat Android de vraag stelt.
/// Alleen als er nog geen toestemming is en de uitleg nog niet getoond is.
Future<void> explainLocationFirst(BuildContext context, {required String why}) async {
  try {
    final p = await Geolocator.checkPermission();
    if (p != LocationPermission.denied) return;
    if (await locationExplained()) return;
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.my_location),
      title: const Text('Je locatie'),
      content: Text('$why\n\nJe locatie blijft van jou: RunWise verkoopt of deelt hem niet. '
          'Je telefoon vraagt zo om toestemming; kies "Tijdens gebruik van de app".'),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Begrepen'))],
    ),
  );
  await markLocationExplained();
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets.dart';

/// Zet een run als afspraak in je agenda (Google Agenda, of de agenda-app die de link opent).
Future<void> addToCalendar(BuildContext context, {required String title, required DateTime start, required int minutes, String details = ''}) async {
  String fmt(DateTime t) {
    final u = t.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}00Z';
  }

  final end = start.add(Duration(minutes: minutes));
  final uri = Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${fmt(start)}/${fmt(end)}',
    'details': details,
  });
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showMessage(context, 'Kon je agenda niet openen.', error: true);
  } catch (_) {
    if (context.mounted) showMessage(context, 'Kon je agenda niet openen.', error: true);
  }
}

import 'dart:io';

import 'package:home_widget/home_widget.dart';

/// Werkt de startscherm-widget "Beste moment vandaag" bij (alleen Android).
class HomeWidgetService {
  HomeWidgetService._();
  static final instance = HomeWidgetService._();

  String? _last;

  Future<void> update({required String label, required String time, required String detail}) async {
    if (!Platform.isAndroid) return;
    final key = '$label|$time|$detail';
    if (key == _last) return;
    _last = key;
    try {
      final now = DateTime.now();
      await HomeWidget.saveWidgetData<String>('label', label);
      await HomeWidget.saveWidgetData<String>('time', time);
      await HomeWidget.saveWidgetData<String>('detail', detail);
      await HomeWidget.saveWidgetData<String>(
          'updated', 'bijgewerkt ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');
      await HomeWidget.updateWidget(androidName: 'BestMomentWidget', qualifiedAndroidName: 'nl.runwise.runwise.BestMomentWidget');
    } catch (_) {
      // Geen widget geplaatst of geen ondersteuning: niets aan de hand.
    }
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../domain/hydration.dart';
import '../../shared/widgets.dart';

const _weightKey = 'body_weight_kg';

/// Vochtverlies na je run en hoeveel je de komende uren drinkt (schatting).
class HydrationCard extends StatefulWidget {
  const HydrationCard({super.key, required this.activity});
  final Activity activity;

  /// Alleen bij runs met weer erbij, van de laatste 2 dagen (daarna heb je er niets meer aan).
  static bool applies(Activity a) =>
      (a.feelsLikeCelsius ?? a.temperatureCelsius) != null &&
      a.movingTimeSeconds >= 20 * 60 &&
      DateTime.now().difference(a.startedAt).inHours <= 48;

  @override
  State<HydrationCard> createState() => _HydrationCardState();
}

class _HydrationCardState extends State<HydrationCard> {
  double? _weight;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _weight = p.getDouble(_weightKey));
    }).ignore();
  }

  Future<void> _editWeight() async {
    var v = _weight ?? 75;
    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Je gewicht')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${v.round()} kg', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            Slider(value: v, min: 40, max: 140, divisions: 100, onChanged: (x) => set(() => v = x)),
            Text(tr('Alleen voor deze schatting; blijft op je telefoon.'), style: TextStyle(color: RwColors.subtle, fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, v.roundToDouble()), child: Text(tr('Bewaren'))),
          ],
        ),
      ),
    );
    if (res == null) return;
    (await SharedPreferences.getInstance()).setDouble(_weightKey, res).ignore();
    if (mounted) setState(() => _weight = res);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final h = hydrationAfter(
      minutes: (a.movingTimeSeconds / 60).round(),
      meters: a.distanceMeters,
      feelsLike: a.feelsLikeCelsius ?? a.temperatureCelsius!,
      humidity: a.humidityPct,
      weightKg: _weight ?? 75,
    );
    if (h == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RwCard(
        title: tr('VOCHT'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.water_drop_outlined, color: RwColors.accent),
            const SizedBox(width: 12),
            Expanded(child: Text(h.text, style: const TextStyle(height: 1.45))),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(
                trf('Schatting uit weer, tempo en gewicht ({kg} kg). Wegen voor en na de run is het nauwkeurigst.', {'kg': (_weight ?? 75).round()}),
                style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.35),
              ),
            ),
            TextButton(onPressed: _editWeight, child: Text(tr('Gewicht'))),
          ]),
        ]),
      ),
    );
  }
}

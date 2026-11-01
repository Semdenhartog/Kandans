import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../data/services/health_consent.dart';
import '../../data/services/heart_rate_service.dart';
import '../../shared/widgets.dart';

/// Schakelaar onder Ik → Account: toestemming voor gezondheidsgegevens geven of intrekken.
class HealthConsentTile extends StatefulWidget {
  const HealthConsentTile({super.key});

  @override
  State<HealthConsentTile> createState() => _HealthConsentTileState();
}

class _HealthConsentTileState extends State<HealthConsentTile> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    HealthConsent.granted().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  Future<void> _toggle(bool v) async {
    if (v) {
      final ok = await HealthConsent.ensure(context);
      if (mounted) setState(() => _on = ok);
      return;
    }
    await HealthConsent.revoke();
    await HeartRateService.instance.disconnect();
    if (!mounted) return;
    setState(() => _on = false);
    showMessage(context, tr('Toestemming ingetrokken. Kadans leest en bewaart geen nieuwe gezondheidsgegevens meer.'));
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: TileIcon(Icons.favorite_border),
      title: Text(tr('Gezondheidsgegevens')),
      subtitle: Text(tr('Hartslag, slaap, HRV en pijntjes gebruiken voor je advies')),
      value: _on ?? false,
      onChanged: _on == null ? null : _toggle,
    );
  }
}

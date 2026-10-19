import 'package:flutter/material.dart';

import '../../data/services/app_lock_service.dart';
import '../../shared/widgets.dart';

/// Aan/uit: RunWise ontgrendelen met je vingerafdruk.
class FingerprintTile extends StatefulWidget {
  const FingerprintTile({super.key});

  @override
  State<FingerprintTile> createState() => _FingerprintTileState();
}

class _FingerprintTileState extends State<FingerprintTile> {
  final _lock = AppLockService.instance;
  bool? _available;

  @override
  void initState() {
    super.initState();
    _lock.isAvailable().then((v) {
      if (mounted) setState(() => _available = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _lock.enabled,
      builder: (context, on, _) => SwitchListTile(
        secondary: const Icon(Icons.fingerprint),
        title: const Text('Ontgrendelen met vingerafdruk'),
        subtitle: Text(_available == false
            ? 'Stel eerst een vingerafdruk of schermvergrendeling in op je telefoon.'
            : 'Je blijft ingelogd; bij openen bevestig je met je vingerafdruk of pincode.'),
        value: on,
        onChanged: _available == false
            ? null
            : (v) async {
                final ok = await _lock.setEnabled(v);
                if (!ok && context.mounted) showMessage(context, 'Vingerafdruk niet bevestigd. Probeer het opnieuw.');
              },
      ),
    );
  }
}

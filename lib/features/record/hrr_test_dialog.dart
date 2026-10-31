import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/heart_rate_service.dart';
import '../../domain/hrr.dart';

/// Eén minuut rustig staan na je run en meten hoeveel je hartslag zakt. Null = overgeslagen of geen signaal.
Future<HrrResult?> runHrrTest(BuildContext context) => showDialog<HrrResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _HrrDialog(),
    );

class _HrrDialog extends StatefulWidget {
  const _HrrDialog();

  @override
  State<_HrrDialog> createState() => _HrrDialogState();
}

class _HrrDialogState extends State<_HrrDialog> {
  static const _seconds = 60;
  final _hr = HeartRateService.instance;
  late final int? _start = _hr.bpm.value;
  int _left = _seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) _finish();
    });
  }

  void _finish() {
    _timer?.cancel();
    final end = _hr.bpm.value;
    final start = _start;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(start == null || end == null ? null : HrrResult(at: DateTime.now(), startBpm: start, endBpm: end));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Hartslagherstel')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Blijf een minuut rustig staan of wandel heel langzaam. Kadans meet hoeveel je hartslag zakt.'),
              textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted, height: 1.4)),
          const SizedBox(height: 16),
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(child: CircularProgressIndicator(value: 1 - _left / _seconds, strokeWidth: 6)),
              ValueListenableBuilder<int?>(
                valueListenable: _hr.bpm,
                builder: (_, bpm, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(bpm?.toString() ?? '–',
                      style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 34, fontWeight: FontWeight.w800)),
                  Text('$_left s', style: TextStyle(color: RwColors.subtle)),
                ]),
              ),
            ]),
          ),
          if (_start != null) ...[
            const SizedBox(height: 8),
            Text(trf('Bij het stoppen: {n} bpm', {'n': _start}), style: TextStyle(color: RwColors.subtle, fontSize: 12)),
          ],
        ]),
        actions: [
          TextButton(
            onPressed: () {
              _timer?.cancel();
              Navigator.of(context).pop();
            },
            child: Text(tr('Overslaan')),
          ),
        ],
      );
}

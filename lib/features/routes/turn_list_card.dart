import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/geo.dart';
import '../../domain/route_geometry.dart';
import '../../domain/route_turns.dart';
import '../../shared/widgets.dart';

/// Pijl die de kant van een afslag op wijst.
class TurnArrow extends StatelessWidget {
  const TurnArrow(this.kind, {super.key, this.size = 22, this.color = RwColors.accent});
  final TurnKind kind;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (kind == TurnKind.uTurn) return Icon(Icons.u_turn_left, size: size, color: color);
    return Transform.rotate(
      angle: kind.screenAngle * math.pi / 180,
      child: Icon(Icons.arrow_upward_rounded, size: size, color: color),
    );
  }
}

/// Routebeschrijving: alle afslagen op een rij, zodat je vooraf weet wat je kunt verwachten.
class TurnListCard extends StatefulWidget {
  const TurnListCard({super.key, required this.track});
  final List<LatLng> track;

  @override
  State<TurnListCard> createState() => _TurnListCardState();
}

class _TurnListCardState extends State<TurnListCard> {
  late final List<RouteTurn> _turns = detectTurns(RouteTrack(widget.track));
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    if (_turns.isEmpty) return const SizedBox.shrink();
    final shown = _all ? _turns : _turns.take(5).toList();
    return RwCard(
      title: 'ROUTEBESCHRIJVING · ${_turns.length} AFSLAGEN',
      child: Column(
        children: [
          for (final t in shown)
            Semantics(
              label: '${t.kind.label} na ${Fmt.km(t.meters, decimals: 1)}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 32, child: TurnArrow(t.kind)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.kind.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text('na ${Fmt.km(t.meters, decimals: 1)}', style: const TextStyle(color: RwColors.muted)),
                  ],
                ),
              ),
            ),
          if (_turns.length > 5)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? 'Minder tonen' : 'Alle ${_turns.length} afslagen tonen'),
              ),
            ),
        ],
      ),
    );
  }
}

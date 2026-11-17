import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/i18n.dart';
import '../../shared/art/wolkje.dart';

class AskCloudy extends StatelessWidget {
  const AskCloudy({required this.mood});
  final WolkjeMood mood;

  static const _goud = Color(0xFFD9BF92);

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tr('Vraag Cloudy, je coach'),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            context.go('/coach');
          },
          child: SizedBox(
            width: 250,
            height: 100,
            child: Stack(children: [
              Positioned(
                left: 0,
                top: 4,
                child: Transform.rotate(
                  angle: -0.07,
                  child: Text(
                    '${tr('vraag Cloudy')}\n→ ${tr('tik hier')}',
                    style: TextStyle(
                      fontFamily: 'Caveat',
                      fontVariations: [FontVariation('wght', 700)],
                      fontSize: 25,
                      height: 1.0,
                      color: _goud,
                      shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: CustomPaint(painter: HandArrowPainter(_goud))),
              Positioned(right: 0, bottom: 0, child: Wolkje(size: 52, mood: mood)),
            ]),
          ),
        ),
      );
}

/// Getekende pijl (variant B van het ontwerp): golvend en dan omlaag naar Wolkje.
class HandArrowPainter extends CustomPainter {
  const HandArrowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final schaduw = Paint()
      ..color = const Color(0x55000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final lijn = Path()
      ..moveTo(112, 50)
      ..cubicTo(132, 62, 150, 40, 170, 48)
      ..cubicTo(182, 53, 188, 59, 194, 66);
    final punt = Path()
      ..moveTo(184, 63)
      ..lineTo(195, 67)
      ..lineTo(196, 55);
    for (final path in [lijn, punt]) {
      canvas.drawPath(path, schaduw);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(HandArrowPainter old) => old.color != color;
}

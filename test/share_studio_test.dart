import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/features/activities/share_studio_screen.dart';

void main() {
  test('indeling van het deelbeeld blijft gelijk na bewaren en teruglezen', () {
    final l = StudioLayout()
      ..lineWidth = 8
      ..labels = false
      ..dim = 0.5;
    l.items[StudioPart.line]!
      ..x = 0.2
      ..y = 0.8
      ..scale = 1.5
      ..color = 0xFFE0884E;
    l.items[StudioPart.pace]!.on = true;

    final back = StudioLayout.decode(l.encode());
    expect(back.lineWidth, 8);
    expect(back.labels, isFalse);
    expect(back.dim, 0.5);
    expect(back.items[StudioPart.line]!.x, 0.2);
    expect(back.items[StudioPart.line]!.y, 0.8);
    expect(back.items[StudioPart.line]!.scale, 1.5);
    expect(back.items[StudioPart.line]!.color, 0xFFE0884E);
    expect(back.items[StudioPart.pace]!.on, isTrue);
  });

  test('kapotte of lege bewaarde indeling geeft de standaard', () {
    for (final s in [null, '', 'geen json', '{"items": 3}']) {
      final l = StudioLayout.decode(s);
      expect(l.items.length, StudioPart.values.length);
      expect(l.items[StudioPart.distance]!.on, isTrue);
      expect(l.items[StudioPart.logo]!.on, isTrue);
    }
  });

  test('waarden buiten het bereik worden teruggezet', () {
    final l = StudioLayout.decode('{"items":{"line":{"x":5,"y":-2,"s":99}},"lw":50,"dim":3}');
    expect(l.items[StudioPart.line]!.x, 1.0);
    expect(l.items[StudioPart.line]!.y, 0.0);
    expect(l.items[StudioPart.line]!.scale, StudioLayout.maxScale);
    expect(l.lineWidth, 12);
    expect(l.dim, 0.7);
  });
}

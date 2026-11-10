import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../data/models/models.dart';

/// Wolkje: de mascotte en coach van Kadans. Een klein pixelwolkje met een gouden rand,
/// dat meeleeft met het weer (regen, zon, wind, kou, nacht) en blij is bij een record.
/// Eigen tekening, geen pakketten. Wipt zachtjes; staat stil bij "minder beweging".
enum WolkjeMood { gewoon, regen, zon, wind, nacht, koud, blij, denkt }

/// Bui van Wolkje bij het weer van een uur (null = gewoon).
WolkjeMood wolkjeVoorWeer(HourWeather? w) {
  if (w == null) return WolkjeMood.gewoon;
  final code = w.weatherCode ?? 0;
  final regen = (w.precipitation ?? 0) >= 0.2 || (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95;
  final sneeuw = (code >= 71 && code <= 77) || code == 85 || code == 86;
  final gevoel = w.feelsLike ?? w.temperature;
  if (sneeuw || gevoel <= 2) return WolkjeMood.koud;
  if (regen) return WolkjeMood.regen;
  if (!w.isDay) return WolkjeMood.nacht;
  if (w.windSpeed >= 30) return WolkjeMood.wind;
  if (gevoel >= 20 && code <= 2) return WolkjeMood.zon;
  return WolkjeMood.gewoon;
}

const _breed = 18, _hoog = 16;

const _kleuren = <String, Color>{
  'W': Color(0xFFF7F2EA), // wolk
  'S': Color(0xFFDCD1BF), // schaduw onder
  'O': Color(0xFFB8955F), // gouden rand
  'E': Color(0xFF211A13), // ogen, mond
  'C': Color(0xFFE3C9A0), // wangen
  'G': Color(0xFFD9BF92), // goud
  'L': Color(0xFFF0DDB6), // licht goud
  'R': Color(0xFF6F8FB0), // regen
  'B': Color(0xFF9FB3C4), // sneeuw/ijs
};

/// Het pixelraster (18 × 16) van Wolkje voor een bui en een animatiestap (0 of 1).
List<List<Color?>> wolkjePixels(WolkjeMood mood, {int stap = 0}) {
  // Lijf van 16 × 11, komt op (1,1).
  const lijf = [
    '......WWWW......',
    '....WWWWWWWW....',
    '...WWWWWWWWWW...',
    '.WWWWWWWWWWWWWW.',
    'WWWWWWWWWWWWWWWW',
    'WWWWEWWWWWWEWWWW',
    'WWWCWWWWWWWWCWWW',
    'WWWWWWWEEWWWWWWW',
    '.WWWWWWWWWWWWWW.',
    '..SSSSSSSSSSSS..',
  ];
  final g = List.generate(_hoog, (_) => List<String?>.filled(_breed, null));
  void zet(int x, int y, String k) {
    if (x >= 0 && x < _breed && y >= 0 && y < _hoog) g[y][x] = k;
  }

  // Zon achter het wolkje.
  if (mood == WolkjeMood.zon) {
    for (final p in const [[14, 0], [15, 0], [13, 1], [14, 1], [15, 1], [16, 1], [14, 2], [15, 2], [16, 2], [17, 0]]) {
      zet(p[0], p[1], 'G');
    }
  }
  for (var y = 0; y < lijf.length; y++) {
    for (var x = 0; x < lijf[y].length; x++) {
      if (lijf[y][x] != '.') zet(x + 1, y + 1, lijf[y][x]);
    }
  }
  // Gouden rand om alles wat lijf is.
  final rand = <List<int>>[];
  for (var y = 0; y < _hoog; y++) {
    for (var x = 0; x < _breed; x++) {
      if (g[y][x] != null) continue;
      bool lijfBij(int xx, int yy) => xx >= 0 && xx < _breed && yy >= 0 && yy < _hoog && (g[yy][xx] == 'W' || g[yy][xx] == 'S');
      if (lijfBij(x - 1, y) || lijfBij(x + 1, y) || lijfBij(x, y - 1) || lijfBij(x, y + 1)) rand.add([x, y]);
    }
  }
  for (final p in rand) {
    g[p[1]][p[0]] = 'O';
  }

  // Ogen: (5,6) en (12,6); mond (8,8),(9,8); wangen (4,7),(13,7).
  switch (mood) {
    case WolkjeMood.regen:
      final d = stap; // druppels vallen
      for (final x in const [4, 8, 12]) {
        zet(x, 13 + d, 'R');
      }
      for (final x in const [6, 10, 14]) {
        zet(x, 14 - d, 'R');
      }
      zet(8, 8, 'W');
      zet(9, 8, 'W');
      zet(7, 9, 'E');
      zet(10, 9, 'E');
      zet(8, 8, 'E');
      zet(9, 8, 'E');
    case WolkjeMood.zon:
      for (var x = 4; x <= 13; x++) {
        zet(x, 6, 'E');
      }
      zet(5, 6, 'L');
      zet(12, 6, 'L');
    case WolkjeMood.wind:
      for (var x = 0; x <= 4; x++) {
        zet(x + stap, 13, 'G');
      }
      for (var x = 7; x <= 12; x++) {
        zet(x - stap, 14, 'G');
      }
      zet(5, 6, 'W');
      zet(4, 6, 'E');
      zet(12, 6, 'W');
      zet(13, 6, 'E');
    case WolkjeMood.nacht:
      zet(5, 6, 'W');
      zet(12, 6, 'W');
      for (final p in const [[4, 6], [5, 6], [12, 6], [13, 6]]) {
        zet(p[0], p[1], 'E');
      }
      if (stap == 0) {
        for (final p in const [[14, 0], [15, 0], [16, 0], [15, 1], [14, 2], [15, 2], [16, 2]]) {
          zet(p[0], p[1], 'L');
        }
      } else {
        for (final p in const [[15, 1], [16, 1], [16, 2], [15, 3], [16, 3]]) {
          zet(p[0], p[1], 'L');
        }
      }
    case WolkjeMood.koud:
      for (var x = 6; x <= 11; x++) {
        zet(x, 1, 'G');
        zet(x, 0, x.isEven ? 'L' : 'G');
      }
      zet(8, 0, 'L');
      for (final p in const [[2, 13], [7, 14], [12, 13], [15, 15], [4, 15]]) {
        zet(p[0], p[1] - stap, 'B');
      }
    case WolkjeMood.blij:
      zet(5, 6, 'W');
      zet(12, 6, 'W');
      for (final p in const [[4, 6], [5, 5], [6, 6], [11, 6], [12, 5], [13, 6]]) {
        zet(p[0], p[1], 'E');
      }
      zet(7, 8, 'E');
      zet(10, 8, 'E');
      zet(8, 9, 'E');
      zet(9, 9, 'E');
      final vonk = stap == 0 ? const [[0, 1], [1, 0], [16, 13], [17, 12], [1, 13]] : const [[0, 0], [17, 1], [16, 12], [0, 14], [17, 14]];
      for (final p in vonk) {
        zet(p[0], p[1], 'L');
      }
    case WolkjeMood.denkt:
      zet(5, 6, 'W');
      zet(12, 6, 'W');
      zet(6, 5, 'E');
      zet(13, 5, 'E');
      for (final x in [14, 16]) {
        zet(x, 13 + (x == 14 ? stap : 1 - stap), 'G');
      }
    case WolkjeMood.gewoon:
      if (stap == 1) {
        // knipoog
        zet(12, 6, 'W');
        zet(11, 6, 'E');
        zet(12, 6, 'E');
      }
  }
  return [for (final r in g) [for (final k in r) k == null ? null : _kleuren[k]]];
}

class Wolkje extends StatefulWidget {
  const Wolkje({super.key, this.mood = WolkjeMood.gewoon, this.size = 72, this.animate = true});

  final WolkjeMood mood;

  /// Breedte; de hoogte is 16/18 daarvan.
  final double size;
  final bool animate;

  @override
  State<Wolkje> createState() => _WolkjeState();
}

class _WolkjeState extends State<Wolkje> {
  Timer? _timer;
  int _stap = 0;
  int _tik = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _plan();
  }

  @override
  void didUpdateWidget(Wolkje oldWidget) {
    super.didUpdateWidget(oldWidget);
    _plan();
  }

  void _plan() {
    final beweeg = widget.animate && !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (!beweeg) {
      _timer?.cancel();
      _timer = null;
      _stap = 0;
      return;
    }
    _timer ??= Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (!mounted) return;
      setState(() {
        _tik++;
        // Gewoon: af en toe knipogen; de rest wisselt elke tik.
        _stap = widget.mood == WolkjeMood.gewoon ? (_tik % 7 == 0 ? 1 : 0) : _tik % 2;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size, h = widget.size * _hoog / _breed;
    final wip = _timer != null && _tik.isOdd ? -w / _breed * 0.6 : 0.0;
    return Semantics(
      label: tr('Wolkje, je coach'),
      image: true,
      child: SizedBox(
        width: w,
        height: h,
        child: Transform.translate(
          offset: Offset(0, wip),
          child: CustomPaint(painter: _WolkjePainter(wolkjePixels(widget.mood, stap: _stap))),
        ),
      ),
    );
  }
}

class _WolkjePainter extends CustomPainter {
  _WolkjePainter(this.pixels);
  final List<List<Color?>> pixels;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / _breed;
    final p = Paint()..isAntiAlias = false;
    for (var y = 0; y < pixels.length; y++) {
      for (var x = 0; x < pixels[y].length; x++) {
        final k = pixels[y][x];
        if (k == null) continue;
        // Iets overlappen tegen naden tussen pixels.
        canvas.drawRect(Rect.fromLTWH(x * c, y * c, c + 0.5, c + 0.5), p..color = k);
      }
    }
  }

  @override
  bool shouldRepaint(_WolkjePainter old) => !identical(old.pixels, pixels);
}

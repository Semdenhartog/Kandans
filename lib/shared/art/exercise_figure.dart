import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Geanimeerd lijnfiguurtje dat een oefening voordoet (zijaanzicht, eigen ontwerp).
/// Werkt met hoeken voor armen en benen; vloeroefeningen met vaste punten (handen/voeten op de grond).

enum Motion {
  stand, jog, walk, hop, highKnees, buttKick, squat, lunge, calfRaise, legSwing, jacks,
  bridge, plank, dog, allFours, birdDog, balance, hipCircles, armCircles, wallStretch, fold, rest,
}

/// Welke beweging hoort bij een oefening (op naam).
Motion motionFor(String name) {
  final n = name.toLowerCase();
  bool has(List<String> ws) => ws.any(n.contains);
  if (has(['bilbrug'])) return Motion.bridge;
  if (has(['plank'])) return Motion.plank;
  if (has(['hond naar beneden', 'neerwaartse hond', 'plank naar hond'])) return Motion.dog;
  if (has(['vogel-hond'])) return Motion.birdDog;
  if (has(['kat en koe', 'draai op handen', 'draad door', 'kindhouding', 'brandkraantje'])) return Motion.allFours;
  if (has(['adem', 'lijf scannen', 'benen tegen de muur', 'liggende', 'dead bug', 'schelpje', 'rugheffen', 'nek los'])) return Motion.rest;
  if (has(['kuitheffen', 'op de tenen', 'op je tenen', 'tenen strekken'])) return Motion.calfRaise;
  if (has(['kuit', 'enkel naar de muur', 'knie naar de muur'])) return Motion.wallStretch;
  if (has(['beenzwaai', 'been zijwaarts'])) return Motion.legSwing;
  if (has(['knieheffen', 'skipping', 'knie omhoog'])) return Motion.highKnees;
  if (has(['hakken'])) return Motion.buttKick;
  if (has(['jumping'])) return Motion.jacks;
  if (has(['uitval', 'opstapje', 'halve knielzit'])) return Motion.lunge;
  if (has(['squat', 'hurkzit', 'kikker'])) return Motion.squat;
  if (has(['balans', 'eenbe'])) return Motion.balance;
  if (has(['heupcirkel', 'heupscharnier'])) return Motion.hipCircles;
  if (has(['armcirkel', 'armen zwaaien', 'borst openen', 'open boek', 'wereldse rek'])) return Motion.armCircles;
  if (has(['sprong', 'hinkel', 'huppel', 'schaats'])) return Motion.hop;
  if (has(['joggen', 'versnelling', 'kruispas'])) return Motion.jog;
  if (has(['wandel', 'lopen', 'losschudden'])) return Motion.walk;
  if (has(['bovenbeen', 'vooroverbuiging', 'achterover', 'onderrug', 'bil', 'heup', 'liezen', 'duif', 'vlinder', '90-90'])) return Motion.fold;
  return Motion.stand;
}

class _Pose {
  _Pose();
  Offset? hip; // vast punt (in lichaamseenheden, y = hoogte boven de grond); null = op de voet zetten
  double torso = 0.08; // vanaf rechtop, + = voorover
  List<double> thigh = [0, 0], knee = [0, 0], arm = [0.15, -0.1], elbow = [0.35, 0.35], pitch = [0, 0];
  List<Offset?> hand = [null, null], foot = [null, null];
  int plant = 0; // welke voet op de grond staat (bij hip == null)
  double plantX = 0;
  double air = 0;
  bool wall = false;
  bool lying = false;
}

const _thighL = 0.245, _shinL = 0.245, _footL = 0.07, _torsoL = 0.3, _upperL = 0.16, _foreL = 0.15, _headR = 0.055;

Offset _down(double a, double l) => Offset(math.sin(a) * l, -math.cos(a) * l); // y omhoog
Offset _up(double a, double l) => Offset(math.sin(a) * l, math.cos(a) * l);

/// Twee botten van [a] naar [target]; [bend] = +1 knie naar voren/boven, -1 naar achteren.
Offset _ik(Offset a, Offset target, double l1, double l2, double bend) {
  var d = target - a;
  var dist = d.distance.clamp(0.001, l1 + l2 - 0.0001);
  d = d / d.distance * dist;
  final cosA = ((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)).clamp(-1.0, 1.0);
  final base = math.atan2(d.dy, d.dx);
  final ang = base + bend * math.acos(cosA);
  return a + Offset(math.cos(ang), math.sin(ang)) * l1;
}

_Pose _poseFor(Motion m, double p) {
  final s = math.sin(p * 2 * math.pi);
  final d = (1 - math.cos(p * 2 * math.pi)) / 2; // 0 → 1 → 0
  final q = _Pose();
  switch (m) {
    case Motion.stand:
      q.torso = 0.06 + 0.02 * s;
      q.arm = [0.12 + 0.05 * s, -0.08];
    case Motion.jog || Motion.walk || Motion.hop:
      final amp = m == Motion.walk ? 0.35 : 0.55;
      q.thigh = [amp * s, -amp * s];
      q.knee = [0.3 + (m == Motion.walk ? 0.2 : 0.9) * math.max(0, -s), 0.3 + (m == Motion.walk ? 0.2 : 0.9) * math.max(0, s)];
      q.arm = [-0.55 * s, 0.55 * s];
      q.elbow = [1.4, 1.4];
      q.torso = m == Motion.walk ? 0.05 : 0.14;
      q.plant = s > 0 ? 1 : 0;
      q.air = m == Motion.hop ? 0.06 * math.sin(p * 4 * math.pi).abs() : (m == Motion.jog ? 0.015 * math.sin(p * 4 * math.pi).abs() : 0);
    case Motion.highKnees:
      q.thigh = [1.5 * math.max(0, s), 1.5 * math.max(0, -s)];
      q.knee = [q.thigh[0] * 1.15, q.thigh[1] * 1.15];
      q.arm = [-0.9 * s, 0.9 * s];
      q.elbow = [1.5, 1.5];
      q.plant = s > 0 ? 1 : 0;
      q.air = 0.02 * math.sin(p * 4 * math.pi).abs();
    case Motion.buttKick:
      q.thigh = [-0.1, -0.1];
      q.knee = [2.4 * math.max(0, s), 2.4 * math.max(0, -s)];
      q.arm = [-0.6 * s, 0.6 * s];
      q.elbow = [1.4, 1.4];
      q.plant = s > 0 ? 1 : 0;
      q.torso = 0.12;
    case Motion.squat:
      q.thigh = [1.35 * d, 1.35 * d];
      q.knee = [2.0 * d, 2.0 * d];
      q.torso = 0.06 + 0.55 * d;
      q.arm = [1.45 * d, 1.35 * d];
      q.elbow = [0.1, 0.1];
    case Motion.lunge:
      q.thigh = [0.25 + 1.1 * d, -0.35 - 0.15 * d];
      q.knee = [0.25 + 1.15 * d, 0.2 + 0.7 * d];
      q.torso = 0.04;
      q.arm = [0.2, -0.2];
      q.elbow = [0.6, 0.6];
    case Motion.calfRaise:
      q.pitch = [0.9 * d, 0.9 * d];
      q.arm = [0.1, -0.1];
    case Motion.legSwing:
      q.plant = 1;
      q.thigh = [0.3 + 0.9 * s, 0];
      q.knee = [0.1, 0];
      q.arm = [1.5, 1.4];
      q.elbow = [0, 0];
      q.wall = true;
    case Motion.jacks:
      q.arm = [0.2 + 2.8 * d, 0.2 + 2.8 * d];
      q.elbow = [0, 0];
      q.thigh = [0.18 * d, -0.18 * d];
      q.air = 0.05 * math.sin(p * 2 * math.pi).abs();
    case Motion.bridge:
      q.lying = true;
      final hy = 0.04 + 0.16 * d;
      q.hip = Offset(0.05, hy);
      q.torso = -math.acos(((0.035 - hy) / _torsoL).clamp(-1.0, 1.0));
      q.foot = [const Offset(0.36, 0.0), const Offset(0.33, 0.0)];
      q.hand = [const Offset(-0.12, 0.0), const Offset(-0.1, 0.0)];
    case Motion.plank:
      q.lying = true;
      q.hip = Offset(0, 0.25 + 0.008 * s);
      q.torso = 1.4;
      q.hand = [const Offset(0.3, 0), const Offset(0.28, 0)];
      q.foot = [const Offset(-0.42, 0), const Offset(-0.4, 0)];
    case Motion.dog:
      q.lying = true;
      q.hip = Offset(0, 0.42 + 0.02 * d);
      q.torso = 2.35;
      q.hand = [const Offset(0.42, 0), const Offset(0.4, 0)];
      q.foot = [Offset(-0.22, 0.0 + 0.03 * d), const Offset(-0.2, 0)];
    case Motion.allFours || Motion.birdDog:
      q.lying = true;
      q.hip = const Offset(0, 0.25);
      q.torso = 1.57 + (m == Motion.allFours ? 0.12 * s : 0);
      q.thigh = [0, 0];
      q.knee = [1.57, 1.57];
      q.hand = [const Offset(0.3, 0), const Offset(0.29, 0)];
      if (m == Motion.birdDog) {
        q.thigh = [-1.45 * d, 0];
        q.knee = [1.57 * (1 - d), 1.57];
        q.hand = [null, const Offset(0.29, 0)];
        q.arm = [0.1 + 2.95 * d, 0];
        q.elbow = [0, 0];
      }
    case Motion.balance:
      q.plant = 1;
      q.thigh = [1.3, 0];
      q.knee = [1.6, 0];
      q.arm = [1.2 + 0.1 * s, -1.0 - 0.1 * s];
      q.elbow = [0, 0];
      q.torso = 0.05 * s;
    case Motion.hipCircles:
      q.torso = 0.15 * s;
      q.plantX = 0.03 * s;
      q.hand = [const Offset(0.04, 0.48), const Offset(-0.04, 0.48)];
    case Motion.armCircles:
      final a = p * 2 * math.pi;
      q.arm = [a, a + 0.25];
      q.elbow = [0, 0];
    case Motion.wallStretch:
      q.wall = true;
      q.thigh = [0.55, -0.45 - 0.05 * d];
      q.knee = [0.65 + 0.1 * d, 0];
      q.torso = 0.45 + 0.05 * d;
      q.arm = [1.65, 1.6];
      q.elbow = [0.1, 0.1];
    case Motion.fold:
      q.torso = 0.3 + 1.1 * d;
      q.arm = [0.05, -0.05];
      q.elbow = [0, 0];
    case Motion.rest:
      q.lying = true;
      q.hip = const Offset(0.05, 0.035);
      q.torso = -1.5 + 0.03 * s;
      q.thigh = [1.5, 1.52];
      q.knee = [0, 0];
      q.arm = [1.45, 1.5];
      q.elbow = [0, 0];
  }
  return q;
}

class _Body {
  _Body(this.hip, this.shoulder, this.head, this.knee, this.ankle, this.toe, this.elbow, this.hand);
  final Offset hip, shoulder, head;
  final List<Offset> knee, ankle, toe, elbow, hand;
}

_Body _solve(_Pose q) {
  // Benen vanaf de heup (relatief).
  List<Offset> kneeRel = [], ankleRel = [], toeRel = [];
  for (var i = 0; i < 2; i++) {
    final k = _down(q.thigh[i], _thighL);
    final a = k + _down(q.thigh[i] - q.knee[i], _shinL);
    final t = a + _down(math.pi / 2 - q.pitch[i], _footL);
    kneeRel.add(k);
    ankleRel.add(a);
    toeRel.add(t);
  }
  Offset hip;
  if (q.hip != null) {
    hip = q.hip!;
  } else {
    // Zet de standvoet op de grond.
    final i = q.plant;
    final low = math.min(toeRel[i].dy, ankleRel[i].dy);
    hip = Offset(q.plantX, -low + 0.02 + q.air);
  }
  final knee = <Offset>[], ankle = <Offset>[], toe = <Offset>[];
  for (var i = 0; i < 2; i++) {
    if (q.foot[i] != null) {
      final target = q.foot[i]! + const Offset(0, 0.02);
      final k = _ik(hip, target, _thighL, _shinL, 1);
      knee.add(k);
      ankle.add(target);
      toe.add(target + Offset(q.torso < 0 ? _footL * 0.9 : -_footL * 0.2, q.torso < 0 ? 0 : -0.01));
    } else {
      knee.add(hip + kneeRel[i]);
      ankle.add(hip + ankleRel[i]);
      toe.add(hip + toeRel[i]);
    }
  }
  final shoulder = hip + _up(q.torso, _torsoL);
  var head = hip + _up(q.torso, _torsoL + 0.04 + _headR);
  if (head.dy < _headR + 0.005) head = Offset(head.dx, _headR + 0.005);
  final elbow = <Offset>[], hand = <Offset>[];
  for (var i = 0; i < 2; i++) {
    if (q.hand[i] != null) {
      final target = q.hand[i]! + const Offset(0, 0.01);
      final e = _ik(shoulder, target, _upperL, _foreL, 1);
      elbow.add(e);
      hand.add(target);
    } else {
      final e = shoulder + _down(q.arm[i], _upperL);
      elbow.add(e);
      hand.add(e + _down(q.arm[i] + q.elbow[i], _foreL));
    }
  }
  return _Body(hip, shoulder, head, knee, ankle, toe, elbow, hand);
}

class ExercisePainter extends CustomPainter {
  ExercisePainter({required this.motion, required this.phase, required this.color, required this.accent, required this.ground});
  final Motion motion;
  final double phase;
  final Color color, accent, ground;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.height * 0.82;
    final gy = size.height * 0.92;
    final cx = size.width / 2;
    final q = _poseFor(motion, phase);
    final b = _solve(q);
    Offset px(Offset o) => Offset(cx + o.dx * unit, gy - o.dy * unit);

    // Grond, schaduw en (soms) een muur.
    canvas.drawLine(Offset(size.width * 0.06, gy), Offset(size.width * 0.94, gy),
        Paint()
          ..color = ground
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round);
    canvas.drawOval(Rect.fromCenter(center: Offset(px(b.hip).dx, gy + 2), width: unit * (q.lying ? 0.7 : 0.32), height: 6),
        Paint()..color = ground.withValues(alpha: 0.5));
    if (q.wall) {
      final wx = px(Offset(math.max(b.hand[0].dx, b.hand[1].dx) + 0.01, 0)).dx;
      canvas.drawLine(Offset(wx, gy), Offset(wx, gy - unit * 1.05),
          Paint()
            ..color = ground
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round);
    }

    final w = unit / 22;
    Paint pen(bool far) => Paint()
      ..color = far ? color.withValues(alpha: 0.4) : color
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    void chain(List<Offset> pts, bool far) {
      final path = Path()..moveTo(px(pts.first).dx, px(pts.first).dy);
      for (final p in pts.skip(1)) {
        path.lineTo(px(p).dx, px(p).dy);
      }
      canvas.drawPath(path, pen(far));
    }

    // Verre kant eerst.
    chain([b.hip, b.knee[1], b.ankle[1], b.toe[1]], true);
    chain([b.shoulder, b.elbow[1], b.hand[1]], true);
    chain([b.hip, b.shoulder], false);
    chain([b.hip, b.knee[0], b.ankle[0], b.toe[0]], false);
    chain([b.shoulder, b.elbow[0], b.hand[0]], false);
    canvas.drawCircle(px(b.head), _headR * unit, pen(false));
    // Accent: de spier die werkt (stip op de knie of heup).
    final dot = switch (motion) {
      Motion.calfRaise || Motion.wallStretch => Offset.lerp(b.knee[motion == Motion.wallStretch ? 1 : 0], b.ankle[motion == Motion.wallStretch ? 1 : 0], 0.4)!,
      Motion.squat || Motion.lunge || Motion.bridge || Motion.hipCircles => b.hip,
      Motion.plank || Motion.birdDog || Motion.allFours => Offset.lerp(b.hip, b.shoulder, 0.5)!,
      _ => null,
    };
    if (dot != null) canvas.drawCircle(px(dot), w * 0.9, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant ExercisePainter old) => old.phase != phase || old.motion != motion || old.color != color;
}

class ExerciseFigure extends StatefulWidget {
  const ExerciseFigure({super.key, required this.name, this.color, this.accent, this.ground});
  final String name;
  final Color? color, accent, ground;

  @override
  State<ExerciseFigure> createState() => _ExerciseFigureState();
}

class _ExerciseFigureState extends State<ExerciseFigure> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: _durationFor(motionFor(widget.name)));

  static Duration _durationFor(Motion m) => switch (m) {
        Motion.jog || Motion.highKnees || Motion.buttKick || Motion.hop => const Duration(milliseconds: 800),
        Motion.walk || Motion.jacks => const Duration(milliseconds: 1100),
        Motion.rest || Motion.fold || Motion.wallStretch || Motion.plank => const Duration(milliseconds: 4200),
        _ => const Duration(milliseconds: 2200),
      };

  @override
  void initState() {
    super.initState();
    if (!WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      _c.repeat();
    } else {
      _c.value = 0.5;
    }
  }

  @override
  void didUpdateWidget(ExerciseFigure old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) {
      _c.duration = _durationFor(motionFor(widget.name));
      if (_c.isAnimating) _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1.25,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: ExercisePainter(
              motion: motionFor(widget.name),
              phase: _c.value,
              color: widget.color ?? cs.onSurface,
              accent: widget.accent ?? cs.primary,
              ground: widget.ground ?? cs.onSurface.withValues(alpha: 0.2),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/theme.dart';

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

const _thighL = 0.245, _shinL = 0.235, _footL = 0.075, _torsoL = 0.29, _upperL = 0.165, _foreL = 0.15, _headR = 0.058;

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
      q.hand = [const Offset(0.02, 0.0), const Offset(0.0, 0.0)];
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
        q.arm = [0.1 + 1.5 * d, 0];
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
    final low = math.min(toeRel[i].dy - 0.017, ankleRel[i].dy - 0.026);
    hip = Offset(q.plantX, -low + q.air);
  }
  final knee = <Offset>[], ankle = <Offset>[], toe = <Offset>[];
  for (var i = 0; i < 2; i++) {
    if (q.foot[i] != null) {
      final target = q.foot[i]! + const Offset(0, 0.026);
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
      final target = q.hand[i]! + const Offset(0, 0.021);
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

/// Luxe weergave: een gebeeldhouwd figuur in champagnegoud op een donker podium,
/// met spotlicht, een spiegelende vloer en een warme gloed op de spier die werkt.
class ExercisePainter extends CustomPainter {
  ExercisePainter({required this.motion, required this.phase});
  final Motion motion;
  final double phase;

  // Vaste kleuren: dit podium is altijd donker-goud (zoals Premium), in licht én donker thema.
  static const _bgTop = Color(0xFF1E1913), _bgBottom = Color(0xFF0A0908);
  static const _hi = Color(0xFFF2DFB3), _base = Color(0xFFD0AB66), _shade = Color(0xFF8A6630);
  static const _farHi = Color(0xFFA88A52), _farBase = Color(0xFF85683A), _farShade = Color(0xFF4A3619);
  static const _glow = Color(0xFFFF9F43);

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.height * 0.8;
    final gy = size.height * 0.87;
    final cx = size.width / 2;
    final q = _poseFor(motion, phase);
    final b = _solve(q);
    Offset px(Offset o) => Offset(cx + o.dx * unit, gy - o.dy * unit);

    _stage(canvas, size, gy, unit, px(b.hip).dx);

    // Spiegeling in de vloer: het figuur ondersteboven, zacht vervagend.
    canvas.saveLayer(Rect.fromLTWH(0, gy, size.width, size.height - gy), Paint());
    canvas.save();
    canvas.translate(0, gy * 2);
    canvas.scale(1, -1);
    _figure(canvas, b, q, px, unit, reflection: true);
    canvas.restore();
    canvas.drawRect(
      Rect.fromLTWH(0, gy, size.width, size.height - gy),
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, gy, size.width, (size.height - gy) * 0.9)),
    );
    canvas.restore();

    if (q.wall) _wall(canvas, size, px(Offset(math.max(b.hand[0].dx, b.hand[1].dx) + 0.012, 0)).dx, gy, unit);
    _figure(canvas, b, q, px, unit);
    _muscleGlow(canvas, b, px, unit);
  }

  void _stage(Canvas canvas, Size size, double gy, double unit, double figureX) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_bgTop, _bgBottom]).createShader(r));
    // Spotlicht van boven.
    final cone = Path()
      ..moveTo(figureX - unit * 0.12, 0)
      ..lineTo(figureX + unit * 0.12, 0)
      ..lineTo(figureX + unit * 0.75, gy)
      ..lineTo(figureX - unit * 0.75, gy)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFFFFE7B0).withValues(alpha: 0.10), const Color(0xFFFFE7B0).withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, gy))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    // Vloer: lichtvlek, gouden rand en een fijne horizon.
    final floor = Rect.fromCenter(center: Offset(figureX, gy + 2), width: unit * 1.5, height: unit * 0.16);
    canvas.drawOval(
      floor,
      Paint()..shader = RadialGradient(colors: [const Color(0xFFFFE7B0).withValues(alpha: 0.16), const Color(0xFFFFE7B0).withValues(alpha: 0)]).createShader(floor),
    );
    canvas.drawLine(
      Offset(size.width * 0.04, gy),
      Offset(size.width * 0.96, gy),
      Paint()
        ..strokeWidth = 1
        ..shader = LinearGradient(colors: [
          const Color(0xFFCFAA62).withValues(alpha: 0),
          const Color(0xFFCFAA62).withValues(alpha: 0.55),
          const Color(0xFFCFAA62).withValues(alpha: 0),
        ]).createShader(Rect.fromLTWH(0, gy, size.width, 1)),
    );
    // Contactschaduw onder het figuur.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(figureX, gy + 1), width: unit * 0.34, height: unit * 0.035),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
  }

  void _wall(Canvas canvas, Size size, double x, double gy, double unit) {
    final rect = Rect.fromLTWH(x, gy - unit * 1.05, unit * 0.05, unit * 1.05);
    canvas.drawRRect(
      RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
      Paint()..shader = const LinearGradient(colors: [Color(0xFF3A3024), Color(0xFF1A1611)]).createShader(rect),
    );
    canvas.drawLine(rect.topLeft, rect.bottomLeft, Paint()..color = const Color(0xFFCFAA62).withValues(alpha: 0.6)..strokeWidth = 1.2);
  }

  /// Een ledemaat als taps toelopende, belichte vorm (licht van linksboven).
  void _limb(Canvas canvas, Offset a, Offset b, double ra, double rb, {required bool far, bool reflection = false}) {
    final d = b - a;
    final len = d.distance;
    if (len < 0.5) {
      canvas.drawCircle(a, ra, Paint()..color = far ? _farBase : _base);
      return;
    }
    final n = Offset(-d.dy / len, d.dx / len);
    // Kant naar het licht (boven/links op het scherm).
    const light = Offset(-0.6, -0.8);
    final lit = (n.dx * light.dx + n.dy * light.dy) >= 0 ? n : -n;
    final mid = Offset.lerp(a, b, 0.5)!;
    final rm = (ra + rb) / 2;
    final hi = far ? _farHi : _hi, base = far ? _farBase : _base, sh = far ? _farShade : _shade;
    final paint = Paint()
      ..isAntiAlias = true
      ..shader = LinearGradient(
        colors: reflection ? [base, sh] : [hi, base, sh],
        stops: reflection ? null : const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromPoints(mid + lit * rm * 1.3, mid - lit * rm * 1.3));
    final path = Path()
      ..moveTo((a + n * ra).dx, (a + n * ra).dy)
      ..lineTo((b + n * rb).dx, (b + n * rb).dy)
      ..arcToPoint(b - n * rb, radius: Radius.circular(rb), clockwise: false)
      ..lineTo((a - n * ra).dx, (a - n * ra).dy)
      ..arcToPoint(a + n * ra, radius: Radius.circular(ra), clockwise: false)
      ..close();
    // Gekozen draairichting kan per hoek verschillen: vul daarom ook de eindcirkels.
    canvas.drawPath(path, paint);
    canvas.drawCircle(a, ra, paint);
    canvas.drawCircle(b, rb, paint);
  }

  void _figure(Canvas canvas, _Body b, _Pose q, Offset Function(Offset) px, double unit, {bool reflection = false}) {
    double r(double v) => v * unit;
    void leg(int i, bool far) {
      _limb(canvas, px(b.hip), px(b.knee[i]), r(0.052), r(0.036), far: far, reflection: reflection);
      _limb(canvas, px(b.knee[i]), px(b.ankle[i]), r(0.036), r(0.022), far: far, reflection: reflection);
      // Schoen: iets breder bij de hak, slank naar de neus.
      _limb(canvas, px(b.ankle[i]), px(b.toe[i]), r(0.026), r(0.017), far: far, reflection: reflection);
    }

    void arm(int i, bool far) {
      _limb(canvas, px(b.shoulder), px(b.elbow[i]), r(0.03), r(0.023), far: far, reflection: reflection);
      _limb(canvas, px(b.elbow[i]), px(b.hand[i]), r(0.023), r(0.017), far: far, reflection: reflection);
      canvas.drawCircle(px(b.hand[i]), r(0.021), Paint()..color = far ? _farBase : _base);
    }

    void joint(Offset o, double rad, bool far) {
      final c = px(o);
      final rr = r(rad);
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.45),
            colors: far ? const [_farHi, _farBase, _farShade] : const [_hi, _base, _shade],
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromCircle(center: c, radius: rr)),
      );
      // Fijne naad rond het gewricht.
      canvas.drawCircle(c, rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, rr * 0.08)
        ..color = (far ? _farShade : _shade).withValues(alpha: 0.55));
    }

    leg(1, true);
    joint(b.knee[1], 0.034, true);
    arm(1, true);
    joint(b.elbow[1], 0.024, true);
    // Romp: bekken, buik en borst als één gebeeldhouwde vorm.
    final chest = Offset.lerp(b.hip, b.shoulder, 0.78)!;
    _limb(canvas, px(b.hip), px(chest), r(0.066), r(0.08), far: false, reflection: reflection);
    _limb(canvas, px(chest), px(b.shoulder), r(0.08), r(0.052), far: false, reflection: reflection);
    final neckTop = Offset.lerp(b.shoulder, b.head, 0.55)!;
    _limb(canvas, px(b.shoulder), px(neckTop), r(0.025), r(0.022), far: false, reflection: reflection);
    // Hoofd: ovaal, gekanteld met de romp.
    final hc = px(b.head);
    final tilt = math.atan2(px(b.head).dx - px(b.shoulder).dx, -(px(b.head).dy - px(b.shoulder).dy));
    canvas.save();
    canvas.translate(hc.dx, hc.dy);
    canvas.rotate(tilt);
    final head = Rect.fromCenter(center: Offset.zero, width: r(_headR * 1.8), height: r(_headR * 2.15));
    canvas.drawOval(
      head,
      Paint()
        ..shader = RadialGradient(center: const Alignment(-0.45, -0.5), radius: 0.95, colors: reflection ? [_base, _shade] : [_hi, _base, _shade], stops: reflection ? null : const [0, 0.5, 1])
            .createShader(head),
    );
    canvas.restore();
    joint(b.hip, 0.05, false);
    leg(0, false);
    joint(b.knee[0], 0.036, false);
    joint(b.ankle[0], 0.022, false);
    joint(b.shoulder, 0.036, false);
    arm(0, false);
    joint(b.elbow[0], 0.025, false);
  }

  void _muscleGlow(Canvas canvas, _Body b, Offset Function(Offset) px, double unit) {
    final spots = switch (motion) {
      Motion.calfRaise || Motion.wallStretch => [Offset.lerp(b.knee[motion == Motion.wallStretch ? 1 : 0], b.ankle[motion == Motion.wallStretch ? 1 : 0], 0.35)!],
      Motion.squat || Motion.lunge => [Offset.lerp(b.hip, b.knee[0], 0.5)!, b.hip],
      Motion.bridge || Motion.hipCircles => [b.hip],
      Motion.plank || Motion.birdDog || Motion.allFours || Motion.dog => [Offset.lerp(b.hip, b.shoulder, 0.45)!],
      Motion.legSwing || Motion.balance => [b.hip],
      Motion.armCircles || Motion.jacks => [b.shoulder],
      Motion.highKnees || Motion.buttKick || Motion.jog || Motion.hop => [Offset.lerp(b.hip, b.knee[0], 0.5)!],
      Motion.fold => [Offset.lerp(b.hip, b.knee[0], 0.5)!],
      _ => <Offset>[],
    };
    final pulse = 0.75 + 0.25 * math.sin(phase * 2 * math.pi);
    for (final s in spots) {
      final c = px(s);
      final rr = unit * 0.11;
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(colors: [_glow.withValues(alpha: 0.55 * pulse), _glow.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: rr)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ExercisePainter old) => old.phase != phase || old.motion != motion;
}

class ExerciseFigure extends StatefulWidget {
  const ExerciseFigure({super.key, required this.name, this.label});
  final String name;

  /// Kleine tekst linksboven op het podium (bijvoorbeeld "Hierna").
  final String? label;

  @override
  State<ExerciseFigure> createState() => _ExerciseFigureState();
}

class _ExerciseFigureState extends State<ExerciseFigure> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: _durationFor(motionFor(widget.name)));

  static Duration _durationFor(Motion m) => switch (m) {
        Motion.jog || Motion.highKnees || Motion.buttKick || Motion.hop => const Duration(milliseconds: 900),
        Motion.walk || Motion.jacks => const Duration(milliseconds: 1200),
        Motion.rest || Motion.fold || Motion.wallStretch || Motion.plank => const Duration(milliseconds: 4800),
        _ => const Duration(milliseconds: 2600),
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
  Widget build(BuildContext context) => ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: 1.2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RwRadius.l),
              border: Border.all(color: const Color(0xFFCFAA62).withValues(alpha: 0.35)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(RwRadius.l),
              child: Stack(fit: StackFit.expand, children: [
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (_, _) => CustomPaint(painter: ExercisePainter(motion: motionFor(widget.name), phase: _ease(_c.value))),
                  ),
                ),
                if (widget.label != null)
                  Positioned(
                    left: 18,
                    top: 14,
                    child: Text(widget.label!.toUpperCase(),
                        style: const TextStyle(color: Color(0xFFCFAA62), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
                  ),
              ]),
            ),
          ),
        ),
      );

  /// Iets langer stilstaan in de uiterste standen: oogt rustiger en echter.
  static double _ease(double t) => t - math.sin(t * 4 * math.pi) / (4 * math.pi) * 0.6;
}

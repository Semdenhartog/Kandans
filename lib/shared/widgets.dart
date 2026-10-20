import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// Kaart met optionele titel, in RunWise-stijl: fijne lichtrand bovenaan (als glas), zachte diepte,
/// en als je erop kunt tikken veert hij een fractie in.
class RwCard extends StatefulWidget {
  const RwCard({super.key, this.title, required this.child, this.padding, this.onTap, this.trailing});

  final String? title;

  /// Knopje rechts naast de titel (bijv. sluiten).
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  State<RwCard> createState() => _RwCardState();
}

class _RwCardState extends State<RwCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final content = Padding(
      padding: w.padding ?? const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (w.title != null) ...[
            Row(
              children: [
                Expanded(child: Text(w.title!, style: RwText.overline)),
                if (w.trailing != null) w.trailing!,
              ],
            ),
            SizedBox(height: w.trailing == null ? 12 : 2),
          ],
          w.child,
        ],
      ),
    );
    return AnimatedScale(
      scale: _down ? 0.985 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: DecoratedBox(
        // Rand: licht aan de bovenkant, wegvallend naar onder.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: 0.11), RwColors.border.withValues(alpha: 0.6), RwColors.border.withValues(alpha: 0.35)],
            stops: const [0, 0.35, 1],
          ),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -8)],
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Material(
            color: RwColors.surface,
            borderRadius: BorderRadius.circular(19),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF18181C), RwColors.surface],
                ),
              ),
              child: w.onTap == null
                  ? content
                  : InkWell(
                      onTap: w.onTap,
                      onHighlightChanged: (v) => setState(() => _down = v),
                      child: content,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Klein blokje met label en waarde (bijv. temperatuur).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RwColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: RwColors.subtle)),
          const SizedBox(height: 4),
          // Altijd op één regel: lange waarden (bijv. "0,0 km") worden iets kleiner in plaats van af te breken.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 19, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Lege-staat met uitleg en optionele knop.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyArt(icon: icon),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: RwColors.muted, height: 1.5)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 240,
                child: FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Illustratie voor lege schermen: gloed, een gestippeld rondje met start en finish, en het icoon in het midden.
/// Komt zacht binnen (iets groter worden en de route die zich tekent).
class EmptyArt extends StatelessWidget {
  const EmptyArt({super.key, required this.icon, this.size = 168});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (_, t, _) => SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _EmptyArtPainter(t),
            child: Center(
              child: Transform.scale(
                scale: 0.85 + 0.15 * t,
                child: Container(
                  width: size * 0.36,
                  height: size * 0.36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: RwColors.surfaceHigh,
                    border: Border.all(color: RwColors.accent.withValues(alpha: 0.6), width: 1.5),
                  ),
                  child: Icon(icon, size: size * 0.18, color: RwColors.accent),
                ),
              ),
            ),
          ),
        ),
      );
}

class _EmptyArtPainter extends CustomPainter {
  _EmptyArtPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          RwColors.accent.withValues(alpha: 0.22 * t),
          RwColors.accentDeep.withValues(alpha: 0.06 * t),
          Colors.transparent,
        ], stops: const [0, 0.6, 1])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Gestippeld, golvend rondje (een route) dat zich tekent.
    final path = Path();
    const n = 120;
    for (var i = 0; i <= n; i++) {
      final a = i / n * 2 * math.pi - math.pi / 2;
      final rr = r * (0.62 + 0.06 * math.sin(a * 3) + 0.03 * math.cos(a * 5));
      final p = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    final metric = path.computeMetrics().first;
    final len = metric.length * t;
    final dash = Paint()
      ..color = RwColors.accent.withValues(alpha: 0.85)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var d = 0.0; d < len; d += 11) {
      canvas.drawPath(metric.extractPath(d, math.min(d + 5, len)), dash);
    }
    if (t > 0.05) {
      final start = metric.getTangentForOffset(0)!.position;
      canvas.drawCircle(start, 5, Paint()..color = RwColors.text);
      final head = metric.getTangentForOffset(len)?.position;
      if (head != null) {
        canvas.drawCircle(head, 9, Paint()..color = RwColors.accent.withValues(alpha: 0.35));
        canvas.drawCircle(head, 5, Paint()..color = RwColors.accentLight);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EmptyArtPainter old) => old.t != t;
}

/// Foutmelding met "Opnieuw proberen".
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Er ging iets mis',
      message: message,
      actionLabel: 'Opnieuw proberen',
      onAction: onRetry,
    );
  }
}

/// Laden: grijze, zacht pulserende kaarten in de vorm van wat er komt (zoals Strava en Garmin),
/// of een draaiend rondje met [spinner].
class LoadingView extends StatefulWidget {
  const LoadingView({super.key, this.spinner = false, this.cards = 3});
  final bool spinner;
  final int cards;

  @override
  State<LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<LoadingView> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Grijze balk met een glanzende streep die eroverheen schuift.
  Widget _bar(double w, double h, {double radius = 8}) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = _c.value * 3 - 1; // -1..2
          return Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment(-1 + t * 2 - 1, 0),
                end: Alignment(1 + t * 2 - 1, 0),
                colors: const [RwColors.surfaceHigh, Color(0xFF2C2C33), RwColors.surfaceHigh],
                stops: const [0.25, 0.5, 0.75],
              ),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    if (widget.spinner) return const Center(child: CircularProgressIndicator());
    return Semantics(
      label: 'Laden',
      child: KeyedSubtree(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.cards; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: RwColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: RwColors.border),
                  ),
                  child: Row(
                    children: [
                      _bar(56, 56, radius: 14),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _bar(140, 14),
                            const SizedBox(height: 10),
                            _bar(double.infinity, 10),
                            const SizedBox(height: 8),
                            _bar(90, 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zwevende melding als pil, met een icoon en een tikje.
void showMessage(BuildContext context, String message, {bool error = false}) {
  error ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: error ? RwColors.danger : RwColors.good, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: error ? const Color(0xFF3A1820) : null,
    ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Verwijderen',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: RwColors.surface,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: const TextStyle(color: RwColors.danger)),
        ),
      ],
    ),
  );
  return result ?? false;
}

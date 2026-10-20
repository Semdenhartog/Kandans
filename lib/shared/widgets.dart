import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Kaart met optionele titel, in RunWise-stijl.
class RwCard extends StatelessWidget {
  const RwCard({super.key, this.title, required this.child, this.padding, this.onTap, this.trailing});

  final String? title;

  /// Knopje rechts naast de titel (bijv. sluiten).
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: RwColors.subtle,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                SizedBox(height: trailing == null ? 10 : 2),
              ],
              child,
            ],
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
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _bar(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: RwColors.surfaceHigh, borderRadius: BorderRadius.circular(8)),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.spinner) return const Center(child: CircularProgressIndicator());
    return Semantics(
      label: 'Laden',
      child: FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
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
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(color: RwColors.surfaceHigh, borderRadius: BorderRadius.circular(14)),
                      ),
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

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFF4A1A24) : null,
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

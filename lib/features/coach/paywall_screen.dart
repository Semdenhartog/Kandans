import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/billing_service.dart';
import '../../shared/widgets.dart';

final _plansProvider = FutureProvider.autoDispose<List<PlanOption>>((ref) async {
  final billing = ref.watch(billingServiceProvider);
  final user = ref.watch(currentUserProvider);
  if (!billing.isAvailable || user == null) return const [];
  return billing.plans(user.id);
});

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _yearly = true;
  bool _busy = false;

  /// Wacht tot de server het abonnement heeft verwerkt (meestal een paar seconden).
  Future<bool> _waitForPremium() async {
    for (var i = 0; i < 15; i++) {
      ref.invalidate(profileProvider);
      final p = await ref.read(profileProvider.future);
      if (p?.isPremium ?? false) return true;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  Future<void> _buy(PlanOption plan) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final bought = await ref.read(billingServiceProvider).buy(user.id, plan);
      if (!bought || !mounted) return;
      final active = await _waitForPremium();
      if (!mounted) return;
      showMessage(
        context,
        active
            ? 'Welkom bij Kadans Premium! Je coach staat klaar.'
            : 'Betaling ontvangen. Je Premium wordt zo geactiveerd.',
      );
      if (context.canPop()) context.pop();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final found = await ref.read(billingServiceProvider).restore(user.id);
      if (!mounted) return;
      if (found) {
        await _waitForPremium();
        if (!mounted) return;
        showMessage(context, 'Je abonnement is teruggezet.');
        if (context.canPop()) context.pop();
      } else {
        showMessage(context, 'Geen actief abonnement gevonden op dit Google-account.');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(_plansProvider);
    final billing = ref.watch(billingServiceProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent),
      body: Stack(children: [
        const Positioned.fill(child: _GoldBackdrop()),
        ListView(
        padding: EdgeInsets.fromLTRB(22, MediaQuery.paddingOf(context).top + kToolbarHeight, 22, 32),
        children: [
          const _Crest(),
          const SizedBox(height: 18),
          const Center(
            child: Text('L I D M A A T S C H A P',
                style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2)),
          ),
          const SizedBox(height: 8),
          const _GoldText(
            'Kadans Premium',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, fontFamily: RwFonts.display, height: 1.05),
          ),
          const SizedBox(height: 6),
          const Text(
            'Je eigen AI-hardloopcoach',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: RwColors.text),
          ),
          const SizedBox(height: 10),
          const Text(
            'Kent je runs, je wedstrijden en het weer. Vraag wat je deze week moet lopen, '
            'hoe je je 10 km aanpakt of wat je aantrekt bij 3 graden en regen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: RwColors.muted, height: 1.5),
          ),
          const SizedBox(height: 22),
          const _GoldRule(),
          const SizedBox(height: 10),
          const _Benefit(icon: Icons.chat_bubble_outline, text: 'Onbeperkt vragen aan je coach (max. 30 per dag)'),
          const _Benefit(icon: Icons.calendar_month_outlined, text: 'Trainingsweken op maat van je doel'),
          const _Benefit(icon: Icons.flag_outlined, text: 'Wedstrijdplan: tempo, kleding en drinken'),
          const _Benefit(icon: Icons.insights_outlined, text: 'Na elke run een persoonlijke analyse'),
          const SizedBox(height: 10),
          const _GoldRule(),
          const SizedBox(height: 22),
          if (!billing.isAvailable)
            const RwCard(
              child: Text(
                'Abonnementen zijn binnenkort beschikbaar. Zodra de app in de Play Store staat, '
                'kun je hier je gratis proefmaand starten.',
                style: TextStyle(color: RwColors.muted, height: 1.5),
              ),
            )
          else
            plans.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => ErrorView(
                message: 'Abonnementen konden niet worden geladen.',
                onRetry: () => ref.invalidate(_plansProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const RwCard(
                    child: Text('Er zijn nu geen abonnementen beschikbaar. Probeer het later opnieuw.',
                        style: TextStyle(color: RwColors.muted)),
                  );
                }
                final selected = list.firstWhere((p) => p.isYearly == _yearly, orElse: () => list.first);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final p in list) ...[
                      _PlanTile(
                        plan: p,
                        selected: identical(p, selected),
                        onTap: () => setState(() => _yearly = p.isYearly),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 6),
                    _GoldButton(
                      onPressed: _busy ? null : () => _buy(selected),
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: _ink))
                          : Text(selected.hasFreeTrial ? 'Start 1 maand gratis' : 'Abonneren',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink, letterSpacing: 0.3)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      selected.hasFreeTrial
                          ? 'De eerste maand is gratis. Daarna ${selected.price} per ${selected.isYearly ? 'jaar' : 'maand'}, '
                              'automatisch verlengd. Zeg op tot 24 uur voor het einde van de proefmaand in Google Play '
                              'en je betaalt niets.'
                          : '${selected.price} per ${selected.isYearly ? 'jaar' : 'maand'}, automatisch verlengd. '
                              'Opzeggen kan altijd in Google Play.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.5),
                    ),
                  ],
                );
              },
            ),
          const SizedBox(height: 16),
          if (billing.isAvailable)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: _gold),
              onPressed: _busy ? null : _restore,
              child: const Text('Aankoop terugzetten'),
            ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _gold),
            onPressed: () => launchUrl(
              Uri.parse('https://play.google.com/store/account/subscriptions'),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Abonnement beheren in Google Play'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _gold),
            onPressed: () => launchUrl(Uri.parse(AppConfig.privacyUrl), mode: LaunchMode.externalApplication),
            child: const Text('Privacyverklaring'),
          ),
        ],
      ),
      ]),
    );
  }
}

const _gold = Color(0xFFD9B45A);
const _goldLight = Color(0xFFF6E3A1);
const _goldDeep = Color(0xFF9C7A2A);
const _ink = Color(0xFF1C1405);
const _goldGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_goldLight, _gold, _goldDeep, _gold],
  stops: [0, 0.38, 0.72, 1],
);

/// Zwart met een warme gouden gloed bovenin en een vleugje korrel.
class _GoldBackdrop extends StatelessWidget {
  const _GoldBackdrop();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -1.05),
              radius: 1.1,
              colors: [Color(0x40D9B45A), Color(0x0FD9B45A), Color(0x00000000)],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
      );
}

/// Een gouden embleem dat zacht oplicht.
class _Crest extends StatelessWidget {
  const _Crest();

  @override
  Widget build(BuildContext context) => Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutBack,
          builder: (_, t, child) => Transform.scale(scale: t, child: child),
          child: Container(
            width: 92,
            height: 92,
            padding: const EdgeInsets.all(2.2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(colors: [_goldLight, _gold, _goldDeep, _gold, _goldLight]),
              boxShadow: [BoxShadow(color: _gold.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 2)],
            ),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFF231B0B), Color(0xFF0A0804)]),
              ),
              child: ShaderMask(
                shaderCallback: (r) => _goldGradient.createShader(r),
                child: const Icon(Icons.auto_awesome, size: 40, color: Colors.white),
              ),
            ),
          ),
        ),
      );
}

class _GoldText extends StatelessWidget {
  const _GoldText(this.text, {required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => _goldGradient.createShader(r),
        child: Text(text, textAlign: TextAlign.center, style: style.copyWith(color: Colors.white)),
      );
}

class _GoldRule extends StatelessWidget {
  const _GoldRule();

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_gold.withValues(alpha: 0), _gold.withValues(alpha: 0.55), _gold.withValues(alpha: 0)]),
        ),
      );
}

class _GoldButton extends StatelessWidget {
  const _GoldButton({required this.onPressed, required this.child});
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: _goldGradient,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: _gold.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: _ink,
            minimumSize: const Size.fromHeight(56),
            shape: const StadiumBorder(),
          ),
          child: child,
        ),
      );
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: _gold, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
          ],
        ),
      );
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan, required this.selected, required this.onTap});
  final PlanOption plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF15110A) : const Color(0xFF0E0E10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _gold : const Color(0x22FFFFFF), width: selected ? 1.6 : 1),
          boxShadow: selected ? [BoxShadow(color: _gold.withValues(alpha: 0.18), blurRadius: 20)] : null,
        ),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? _gold : RwColors.subtle),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(plan.isYearly ? 'Per jaar' : 'Per maand',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    if (plan.isYearly) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(gradient: _goldGradient, borderRadius: BorderRadius.circular(20)),
                        child: const Text('BESTE KEUZE',
                            style: TextStyle(color: _ink, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ),
                    ],
                  ]),
                  if (plan.isYearly)
                    const Text('4 maanden gratis vergeleken met per maand',
                        style: TextStyle(color: _gold, fontSize: 12)),
                ],
              ),
            ),
            Text(plan.price, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, fontFamily: RwFonts.display, fontFeatures: rwTnum)),
          ],
        ),
      ),
    );
  }
}

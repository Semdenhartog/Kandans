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
            ? 'Welkom bij RunWise Premium! Je coach staat klaar.'
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
      appBar: AppBar(title: const Text('RunWise Premium')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Icon(Icons.auto_awesome, color: RwColors.accent, size: 44),
          const SizedBox(height: 12),
          const Text(
            'Je eigen AI-hardloopcoach',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Kent je runs, je wedstrijden en het weer. Vraag wat je deze week moet lopen, '
            'hoe je je 10 km aanpakt of wat je aantrekt bij 3 graden en regen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: RwColors.muted, height: 1.5),
          ),
          const SizedBox(height: 20),
          const _Benefit(icon: Icons.chat_bubble_outline, text: 'Onbeperkt vragen aan je coach (max. 30 per dag)'),
          const _Benefit(icon: Icons.calendar_month_outlined, text: 'Trainingsweken op maat van je doel'),
          const _Benefit(icon: Icons.flag_outlined, text: 'Wedstrijdplan: tempo, kleding en drinken'),
          const SizedBox(height: 20),
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
                    FilledButton(
                      onPressed: _busy ? null : () => _buy(selected),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : Text(selected.hasFreeTrial ? 'Start 1 maand gratis' : 'Abonneren',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
              onPressed: _busy ? null : _restore,
              child: const Text('Aankoop terugzetten'),
            ),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('https://play.google.com/store/account/subscriptions'),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Abonnement beheren in Google Play'),
          ),
          TextButton(
            onPressed: () => launchUrl(Uri.parse(AppConfig.privacyUrl), mode: LaunchMode.externalApplication),
            child: const Text('Privacyverklaring'),
          ),
        ],
      ),
    );
  }
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
            Icon(icon, color: RwColors.accent, size: 20),
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
          color: RwColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? RwColors.accent : RwColors.border, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? RwColors.accent : RwColors.subtle),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.isYearly ? 'Per jaar' : 'Per maand',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  if (plan.isYearly)
                    const Text('Voordeligst: 4 maanden gratis vergeleken met per maand',
                        style: TextStyle(color: RwColors.accent, fontSize: 12)),
                ],
              ),
            ),
            Text(plan.price, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/billing_service.dart';
import '../../shared/widgets.dart';
import '../profile/privacy_screen.dart';

/// Premium-pagina: uitleg in donker-goud, daarna de paywall van RevenueCat
/// (maand, jaar of lifetime). Met Premium: het Customer Center om te beheren.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
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

  /// Voert een betaalactie uit met laadrondje en nette foutmelding.
  Future<void> _run(Future<void> Function(String userId) action) async {
    final user = ref.read(currentUserProvider);
    if (user == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action(user.id);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPaywall() => _run((userId) async {
        final outcome = await ref.read(billingServiceProvider).presentPaywall(userId);
        if (outcome == PaywallOutcome.closed || !mounted) return;
        final active = await _waitForPremium();
        if (!mounted) return;
        showMessage(
          context,
          active
              ? tr('Welkom bij Kadans Premium! Je coach staat klaar.')
              : tr('Betaling ontvangen. Je Premium wordt zo geactiveerd.'),
        );
        if (active && context.canPop()) context.pop();
      });

  Future<void> _openCustomerCenter() => _run((userId) async {
        await ref.read(billingServiceProvider).presentCustomerCenter(
              userId,
              onRestored: () => ref.invalidate(profileProvider),
            );
        // Opgezegd of gewijzigd? De server weet het via de webhook; even verversen.
        ref.invalidate(profileProvider);
      });

  Future<void> _restore() => _run((userId) async {
        final found = await ref.read(billingServiceProvider).restore(userId);
        if (!mounted) return;
        if (!found) {
          showMessage(context, tr('Geen aankoop gevonden op dit Google-account.'));
          return;
        }
        await _waitForPremium();
        if (!mounted) return;
        showMessage(context, tr('Je aankoop is teruggezet.'));
      });

  @override
  Widget build(BuildContext context) {
    final billing = ref.watch(billingServiceProvider);
    final serverPremium = ref.watch(profileProvider).value?.isPremium ?? false;
    final storePremium = ref.watch(revenueCatPremiumProvider).value ?? false;
    final premium = serverPremium || storePremium;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, foregroundColor: rwZandAvond.text),
      // Altijd donker en goud, ook als de app licht staat.
      body: DefaultTextStyle.merge(style: TextStyle(color: rwZandAvond.text), child: Stack(children: [
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
          Text(
            'Je eigen AI-hardloopcoach',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: rwZandAvond.text),
          ),
          const SizedBox(height: 10),
          Text(
            'Kent je runs, je wedstrijden en het weer. Vraag wat je deze week moet lopen, '
            'hoe je je 10 km aanpakt of wat je aantrekt bij 3 graden en regen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: rwZandAvond.muted, height: 1.5),
          ),
          const SizedBox(height: 22),
          const _GoldRule(),
          const SizedBox(height: 10),
          const _Benefit(icon: Icons.chat_bubble_outline, text: 'Onbeperkt vragen aan je coach (max. 30 per dag)'),
          const _Benefit(icon: Icons.calendar_month_outlined, text: 'Trainingsweken op maat van je doel'),
          const _Benefit(icon: Icons.flag_outlined, text: 'Wedstrijdplan: tempo, kleding en drinken'),
          const _Benefit(icon: Icons.insights_outlined, text: 'Na elke run een persoonlijke analyse'),
          const _Benefit(icon: Icons.auto_awesome_outlined, text: 'Luxe-posterstijlen en gouden deelkaart inbegrepen'),
          const SizedBox(height: 10),
          const _GoldRule(),
          const SizedBox(height: 22),
          if (!billing.isAvailable)
            _DarkNote(
              text: billing.isTestStoreKey
                  ? tr('Deze versie gebruikt de testsleutel van RevenueCat. Die werkt alleen in een testversie van de app, '
                      'niet in deze APK. Abonnementen zijn hier daarom nog niet beschikbaar.')
                  : 'Abonnementen zijn binnenkort beschikbaar. Zodra de app in de Play Store staat, '
                      'kun je hier je gratis proefmaand starten.',
            )
          else if (premium) ...[
            _DarkNote(text: tr('Je hebt Kadans Premium. Bedankt voor je steun!')),
            const SizedBox(height: 16),
            _GoldButton(
              onPressed: _busy ? null : _openCustomerCenter,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: _ink))
                  : Text(tr('Abonnement beheren'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink, letterSpacing: 0.3)),
            ),
          ] else ...[
            _GoldButton(
              onPressed: _busy ? null : _openPaywall,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: _ink))
                  : Text(tr('Kies je lidmaatschap'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink, letterSpacing: 0.3)),
            ),
            const SizedBox(height: 10),
            Text(
              tr('Per maand, per jaar of één keer voor altijd. Abonnementen verlengen automatisch; '
                  'opzeggen kan altijd in Google Play.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: rwZandAvond.subtle, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 14),
            const _Promise(),
          ],
          const SizedBox(height: 16),
          if (billing.isAvailable && !premium)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: _gold),
              onPressed: _busy ? null : _restore,
              child: Text(tr('Aankoop terugzetten')),
            ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _gold),
            onPressed: () => openPrivacy(context),
            child: const Text('Privacyverklaring'),
          ),
        ],
      ),
      ])),
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

/// Onze belofte (antwoord op de grootste ergernis bij andere loopapps: gratis functies die achter een betaalmuur verdwijnen).
class _Promise extends StatelessWidget {
  const _Promise();

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final (icon, text) in [
          (Icons.lock_open, 'Wat gratis is, blijft gratis. We zetten nooit iets achter de betaalmuur dat je nu gratis hebt.'),
          (Icons.notifications_active_outlined, 'Gaat de prijs ooit omhoog, dan hoor je dat ruim van tevoren in de app.'),
          (Icons.download_outlined, 'Je runs zijn van jou: alles exporteren kan altijd, ook zonder Premium.'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 16, color: _gold),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: rwZandAvond.muted, fontSize: 12.5, height: 1.45))),
            ]),
          ),
      ]);
}

/// Mededeling in de donker-gouden stijl van Premium (ook als de app licht staat).
class _DarkNote extends StatelessWidget {
  const _DarkNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: rwZandAvond.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _gold.withValues(alpha: 0.45)),
        ),
        child: Text(text, style: TextStyle(color: rwZandAvond.muted, height: 1.5)),
      );
}

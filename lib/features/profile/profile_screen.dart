import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/performance_model.dart';
import '../../shared/widgets.dart';
import '../dashboard/dashboard_providers.dart';
import 'connections_card.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final data = await ref.read(repositoryProvider).exportAll();
      final text = const JsonEncoder.withIndent('  ').convert(data);
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        showMessage(context, 'Al je gegevens zijn als tekst (JSON) gekopieerd. Plak ze bijvoorbeeld in een e-mail aan jezelf.');
      }
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Account definitief verwijderen?',
      message: 'Al je runs, routes, wedstrijden, coachgesprekken en koppelingen en je account worden direct en definitief verwijderd. '
          'Dit kan niet ongedaan worden gemaakt.\n\n'
          'Heb je Premium? Zeg je abonnement dan ook op in Google Play, anders loopt de betaling door.',
      confirmLabel: 'Definitief verwijderen',
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteAccount();
      // De router stuurt automatisch naar het inlogscherm.
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final profile = ref.watch(profileProvider);
    final insights = ref.watch(insightsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ik')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          RwCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: RwColors.accent,
                  child: Text(
                    profile.when(
                      data: (p) => (p?.displayName ?? '?').characters.first.toUpperCase(),
                      loading: () => '',
                      error: (_, _) => '?',
                    ),
                    style: const TextStyle(color: RwColors.accentDark, fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.when(
                          data: (p) => p?.displayName ?? '',
                          loading: () => '',
                          error: (_, _) => '',
                        ),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      Text(user?.email ?? '', style: const TextStyle(color: RwColors.subtle)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _InsightsCard(insights: insights),
          const SizedBox(height: 12),
          const ConnectionsCard(),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_awesome, color: RwColors.accent),
                  title: const Text('AI-coach'),
                  subtitle: const Text('Vraag advies over je training'),
                  onTap: () => context.push('/coach'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text('RunWise Premium'),
                  subtitle: Text(
                    profile.value?.isPremium ?? false ? 'Actief' : '1 maand gratis, daarna €5 p/m of €40 p/j',
                  ),
                  onTap: () => context.push('/premium'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacyverklaring'),
                  onTap: () => launchUrl(Uri.parse(AppConfig.privacyUrl), mode: LaunchMode.externalApplication),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Mijn gegevens kopiëren'),
                  subtitle: const Text('Al je gegevens als tekst (AVG)'),
                  onTap: () => _export(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Uitloggen'),
                  onTap: () => ref.read(supabaseProvider).auth.signOut(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined, color: RwColors.danger),
                  title: const Text('Account verwijderen', style: TextStyle(color: RwColors.danger)),
                  onTap: () => _deleteAccount(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'RunWise 1.0 · Weerdata via Open-Meteo.com',
            textAlign: TextAlign.center,
            style: TextStyle(color: RwColors.subtle, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.insights});
  final PerformanceInsights insights;

  String _fmtTemp(double t) => '${t.round()}°C';

  @override
  Widget build(BuildContext context) {
    final i = insights;
    if (!i.isPersonal) {
      final left = PerformanceInsights.minRuns - i.sampleSize;
      return RwCard(
        title: 'JOUW LOOPPROFIEL',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nog $left run${left == 1 ? '' : 's'} met weerdata te gaan',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Na 8 runs berekent RunWise bij welke temperatuur en wind jij het snelst loopt. '
              'Tot die tijd gaan we uit van 8–16°C als ideaal.',
              style: TextStyle(color: RwColors.muted, height: 1.5),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: i.sampleSize / PerformanceInsights.minRuns,
              backgroundColor: RwColors.surfaceHigh,
              color: RwColors.accent,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
          ],
        ),
      );
    }

    final lines = <(IconData, String)>[
      (
        Icons.thermostat,
        'Je loopt het snelst tussen ${_fmtTemp(i.optimalMin)} en ${_fmtTemp(i.optimalMax)}'
            '${i.pctFasterInOptimal != null && i.pctFasterInOptimal! >= 1 ? ', ${i.pctFasterInOptimal!.toStringAsFixed(0)}% sneller dan bij je slechtste temperatuur.' : '.'}'
      ),
      if (i.windSecPerKmPer10kmh != null)
        (
          Icons.air,
          i.windSecPerKmPer10kmh! < 2
              ? 'Wind heeft weinig invloed op jouw tempo.'
              : 'Per 10 km/u extra wind loop je ongeveer ${i.windSecPerKmPer10kmh!.round()} sec/km langzamer.'
        ),
      if (i.preferredTimeOfDay != null && i.morningPace != null && i.eveningPace != null)
        (
          Icons.schedule,
          switch (i.preferredTimeOfDay) {
            'morning' => 'Je bent een ochtendloper: gemiddeld ${Fmt.pace(i.morningPace!)} tegen ${Fmt.pace(i.eveningPace!)} in de avond.',
            'evening' => 'Je loopt sneller in de avond: ${Fmt.pace(i.eveningPace!)} tegen ${Fmt.pace(i.morningPace!)} in de ochtend.',
            _ => 'Ochtend of avond maakt voor jou weinig uit.',
          }
        ),
    ];

    return RwCard(
      title: 'JOUW LOOPPROFIEL · ${i.sampleSize} RUNS${i.isHighConfidence ? '' : ' · VOORLOPIG'}',
      child: Column(
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(l.$1, color: RwColors.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l.$2, style: const TextStyle(height: 1.45))),
                ],
              ),
            ),
          if (i.buckets.length >= 2) ...[
            const SizedBox(height: 8),
            _BucketChart(insights: i),
          ],
        ],
      ),
    );
  }
}

/// Staafjes: relatief tempo per temperatuurgroep (hoger = sneller).
class _BucketChart extends StatelessWidget {
  const _BucketChart({required this.insights});
  final PerformanceInsights insights;

  @override
  Widget build(BuildContext context) {
    final b = insights.buckets;
    final speeds = b.map((x) => 1 / x.relativePace).toList();
    final minS = speeds.reduce((a, c) => a < c ? a : c);
    final maxS = speeds.reduce((a, c) => a > c ? a : c);
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var k = 0; k < b.length; k++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FractionallySizedBox(
                        heightFactor: maxS == minS ? 0.7 : 0.25 + 0.75 * (speeds[k] - minS) / (maxS - minS),
                        child: Container(
                          decoration: BoxDecoration(
                            color: b[k].from >= insights.optimalMin && b[k].to <= insights.optimalMax
                                ? RwColors.accent
                                : RwColors.bar,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${b[k].from.round()}°', style: const TextStyle(fontSize: 11, color: RwColors.subtle)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

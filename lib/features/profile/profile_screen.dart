import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/disk_image_cache.dart';
import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/performance_model.dart';
import '../../data/services/offline_cache.dart';
import '../../domain/badges.dart' show computeBadges;
import '../../domain/shoes.dart';
import '../../shared/widgets.dart';
import '../dashboard/dashboard_providers.dart';
import '../activities/badges_screen.dart';
import '../activities/strength_screen.dart';
import 'connections_card.dart';
import 'emergency_contact.dart';
import 'fingerprint_tile.dart';
import '../planner/training_plan_screen.dart';
import 'heart_rate_screen.dart';
import 'reminder_tile.dart';

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
                    style: const TextStyle(color: RwColors.accentDark, fontSize: 22, fontWeight: FontWeight.w800, fontFamily: RwFonts.display, fontFeatures: rwTnum),
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
          const SizedBox(height: 4),
          Consumer(builder: (context, ref, _) {
            final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
            final km = runs.fold<double>(0, (s, a) => s + a.distanceMeters / 1000);
            final badges = computeBadges(runs).where((b) => b.earned).length;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(child: StatTile(label: 'Runs', value: '${runs.length}')),
                  const SizedBox(width: 8),
                  Expanded(child: StatTile(label: 'Totaal', value: '${km.round()} km')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => openBadges(context),
                      child: StatTile(label: 'Badges', value: '$badges'),
                    ),
                  ),
                ],
              ),
            );
          }),
          const _SectionTitle('TRAINING'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined, color: RwColors.accent),
                  title: const Text('Trainingsschema'),
                  subtitle: const Text('Een schema op maat naar je wedstrijd of afstand'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openTrainingPlan(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: RwColors.accent),
                  title: const Text('Wedstrijden'),
                  subtitle: const Text('Je doelen, voorspelde eindtijd en wedstrijdadvies'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/me/races'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.military_tech_outlined, color: RwColors.accent),
                  title: const Text('Badges'),
                  subtitle: const Text('Mijlpalen en weerbadges'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openBadges(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.fitness_center, color: RwColors.accent),
                  title: const Text('Kracht en mobiliteit'),
                  subtitle: const Text('Warming-up, kracht voor lopers en rekken, met de stem erbij'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openStrength(context),
                ),
                const Divider(height: 1, indent: 56),
                Consumer(builder: (context, ref, _) {
                  final shoes = ref.watch(shoesProvider).value ?? const <Shoe>[];
                  final runs = ref.watch(activitiesProvider).value ?? const <Activity>[];
                  final worn = shoes.where((s) => !s.retired && shoeWornOut(s, runs)).toList();
                  final d = defaultShoe(shoes);
                  return ListTile(
                    leading: Icon(Icons.directions_walk, color: worn.isEmpty ? RwColors.accent : RwColors.danger),
                    title: const Text('Mijn schoenen'),
                    subtitle: Text(
                      worn.isNotEmpty
                          ? '${worn.first.name} is aan vervanging toe'
                          : d == null
                              ? 'Houd bij hoeveel km je schoenen hebben'
                              : '${d.name} \u00b7 ${shoeKm(d, runs).round()} km',
                      style: TextStyle(color: worn.isEmpty ? null : RwColors.danger),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/me/shoes'),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _InsightsCard(insights: insights),
          const _SectionTitle('APPARATEN EN KOPPELINGEN'),
          const ConnectionsCard(),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.monitor_heart_outlined),
              title: const Text('Hartslagband'),
              subtitle: const Text('Live hartslag en zones via Bluetooth'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openHeartRateScreen(context),
            ),
          ),
          const _SectionTitle('MELDINGEN EN VEILIGHEID'),
          const Card(
            child: Column(
              children: [
                ReminderTile(),
                Divider(height: 1, indent: 56),
                EmergencyContactTile(),
                Divider(height: 1, indent: 56),
                FingerprintTile(),
              ],
            ),
          ),
          const _SectionTitle('ACCOUNT'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined, color: RwColors.accent),
                  title: const Text('RunWise Premium'),
                  subtitle: Text(
                    profile.value?.isPremium ?? false ? 'Actief' : '1 maand gratis, daarna €5 p/m of €40 p/j',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/premium'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacyverklaring'),
                  onTap: () => launchUrl(Uri.parse(AppConfig.privacyUrl), mode: LaunchMode.externalApplication),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Mijn gegevens kopiëren'),
                  subtitle: const Text('Al je gegevens als tekst (AVG)'),
                  onTap: () => _export(context, ref),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Uitloggen'),
                  onTap: () async {
                    await OfflineCache.clear();
                    await DiskImageCache.instance.clear();
                    await ref.read(supabaseProvider).auth.signOut();
                  },
                ),
                const Divider(height: 1, indent: 56),
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
            'RunWise 1.0 · Weer via Open-Meteo.com · Buien via Buienradar.nl',
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Text(text, style: const TextStyle(fontSize: 13, color: RwColors.subtle, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      );
}

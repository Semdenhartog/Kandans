import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/disk_image_cache.dart';
import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/services/community_service.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/performance_model.dart';
import '../../data/services/offline_cache.dart';
import '../../domain/badges.dart' show computeBadges;
import '../../domain/shoes.dart';
import '../../shared/widgets.dart';
import '../challenges/invite_card.dart';
import '../dashboard/dashboard_providers.dart';
import '../activities/badges_screen.dart';
import '../challenges/challenges.dart' show openChallenges;
import '../activities/strength_screen.dart';
import 'appearance_tile.dart';
import 'connections_card.dart';
import 'emergency_contact.dart';
import 'fingerprint_tile.dart';
import '../planner/training_plan_screen.dart';
import 'privacy_screen.dart';
import 'heart_rate_screen.dart';
import 'help_screen.dart';
import 'member_card.dart';
import 'reminder_tile.dart';
import '../shop/shop_tile.dart';
import '../../domain/clothing.dart';
import '../../domain/run_goal.dart';
import '../../domain/run_warnings.dart';
import 'sources_screen.dart';
import '../../core/i18n.dart';
import '../../data/services/run_pause_store.dart';
import 'run_pause_tile.dart';

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
      title: tr('Account definitief verwijderen?'),
      message: tr('Al je runs, routes, wedstrijden, coachgesprekken en koppelingen en je account worden direct en definitief verwijderd. '
          'Dit kan niet ongedaan worden gemaakt.\n\n'
          'Heb je Premium? Zeg je abonnement dan ook op in Google Play, anders loopt de betaling door.'),
      confirmLabel: tr('Definitief verwijderen'),
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(tr('Ik')),
        actions: [
          IconButton(
            tooltip: tr('Zoeken in Ik'),
            icon: Icon(Icons.search),
            onPressed: () => showSettingsSearch(context),
          ),
          IconButton(
            tooltip: tr('Hulp'),
            icon: Icon(Icons.help_outline),
            onPressed: () => openHelp(context),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Consumer(builder: (context, ref, _) {
            final runs = ref.watch(activitiesProvider).value ?? <Activity>[];
            final km = runs.fold<double>(0, (s, a) => s + a.distanceMeters / 1000);
            final badges = computeBadges(runs, pausedWeeks: ref.watch(pausedWeeksProvider)).where((b) => b.earned).length;
            DateTime? since;
            for (final r in runs) {
              if (since == null || r.startedAt.isBefore(since)) since = r.startedAt;
            }
            final p = profile.value;
            final name = (p?.fullName?.trim().isNotEmpty ?? false) ? p!.fullName!.trim() : (p?.displayName ?? '');
            return Padding(
              padding: EdgeInsets.only(top: 4, bottom: 4),
              child: MemberCard(
                name: name,
                email: user?.email ?? '',
                runs: runs.length,
                km: km,
                badges: badges,
                since: since?.toLocal(),
                premium: p?.isPremium ?? false,
                onBadges: () => openBadges(context),
              ),
            );
          }),
          Padding(
            padding: EdgeInsets.only(top: 10, left: 4),
            child: Text(user?.email ?? '', style: TextStyle(color: RwColors.subtle, fontSize: 13)),
          ),
          SizedBox(height: 14),
          ShopTile(),
          const _SectionTitle('TRAINING'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: TileIcon(Icons.calendar_month_outlined, color: RwColors.accent),
                  title: Text(tr('Trainingsschema')),
                  subtitle: Text(tr('Een schema op maat naar je wedstrijd of afstand')),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () => openTrainingPlan(context),
                ),
                Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.flag_outlined, color: RwColors.accent),
                  title: Text(tr('Wedstrijden')),
                  subtitle: Text(tr('Je doelen, voorspelde eindtijd en wedstrijdadvies')),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () => context.go('/me/races'),
                ),
                Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.emoji_events_outlined, color: RwColors.accent),
                  title: Text(tr('Uitdagingen')),
                  subtitle: Text(tr('Doe mee aan een maand- of seizoensuitdaging')),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () => openChallenges(context),
                ),
                Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.military_tech_outlined, color: RwColors.accent),
                  title: Text(tr('Badges')),
                  subtitle: Text(tr('Mijlpalen en weerbadges')),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () => openBadges(context),
                ),
                Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.fitness_center, color: RwColors.accent),
                  title: Text(tr('Kracht en mobiliteit')),
                  subtitle: Text(tr('Warming-up, kracht voor lopers en rekken, met de stem erbij')),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () => openStrength(context),
                ),
                Divider(height: 1, indent: 56),
                Consumer(builder: (context, ref, _) {
                  final rain = ref.watch(rainPreferenceProvider);
                  return ListTile(
                    leading: TileIcon(Icons.umbrella_outlined, color: RwColors.accent),
                    title: Text(tr('Lopen in de regen')),
                    subtitle: Text(tr(rain.label)),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => _pickRain(context, ref),
                  );
                }),
                Divider(height: 1, indent: 56),
                // Je doel (uit de rondleiding), later aan te passen. Gaat mee naar de coach.
                ValueListenableBuilder<RunGoal?>(
                  valueListenable: runGoalNotifier,
                  builder: (context, goal, _) => ListTile(
                    leading: TileIcon(Icons.emoji_events_outlined, color: RwColors.accent),
                    title: Text(tr('Mijn doel')),
                    subtitle: Text(goal == null ? tr('Nog niet gekozen') : tr(goal.label)),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () async {
                      final current = goal ?? await savedRunGoal();
                      if (!context.mounted) return;
                      await _pickOption<RunGoal?>(
                        context,
                        title: tr('Waarvoor loop je?'),
                        values: RunGoal.values,
                        current: current,
                        label: (v) => v!.label,
                        explanation: (v) => v!.explanation,
                        onPick: (v) => saveRunGoal(v!),
                      );
                    },
                  ),
                ),
                Divider(height: 1, indent: 56),
                Consumer(builder: (context, ref, _) {
                  final feel = ref.watch(clothingFeelProvider);
                  return ListTile(
                    leading: TileIcon(Icons.checkroom_outlined, color: RwColors.accent),
                    title: Text(tr('Kledingadvies')),
                    subtitle: Text(tr(feel.label)),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => _pickOption<ClothingFeel>(
                      context,
                      title: tr('Hoe snel heb je het koud?'),
                      values: ClothingFeel.values,
                      current: feel,
                      label: (v) => v.label,
                      explanation: (v) => v.explanation,
                      onPick: (v) => ref.read(clothingFeelProvider.notifier).set(v),
                    ),
                  );
                }),
                Divider(height: 1, indent: 56),
                Consumer(builder: (context, ref, _) {
                  final pollen = ref.watch(pollenSensitivityProvider);
                  return ListTile(
                    leading: TileIcon(Icons.local_florist_outlined, color: RwColors.accent),
                    title: Text(tr('Hooikoorts en pollen')),
                    subtitle: Text(tr(pollen.label)),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => _pickOption<PollenSensitivity>(
                      context,
                      title: tr('Heb je last van pollen?'),
                      values: PollenSensitivity.values,
                      current: pollen,
                      label: (v) => v.label,
                      explanation: (v) => v.explanation,
                      onPick: (v) => ref.read(pollenSensitivityProvider.notifier).set(v),
                    ),
                  );
                }),
                Divider(height: 1, indent: 56),
                Consumer(builder: (context, ref, _) {
                  final dog = ref.watch(dogModeProvider);
                  return SwitchListTile(
                    secondary: TileIcon(Icons.pets_outlined, color: RwColors.accent),
                    title: Text(tr('Ik loop met mijn hond')),
                    subtitle: Text(tr('Waarschuwingen voor heet asfalt, strooizout en lange runs')),
                    value: dog,
                    onChanged: (v) => ref.read(dogModeProvider.notifier).set(v),
                  );
                }),
                Divider(height: 1, indent: 56),
                Consumer(builder: (context, ref, _) {
                  final shoes = ref.watch(shoesProvider).value ?? <Shoe>[];
                  final runs = ref.watch(activitiesProvider).value ?? <Activity>[];
                  final worn = shoes.where((s) => !s.retired && shoeWornOut(s, runs)).toList();
                  final d = defaultShoe(shoes);
                  return ListTile(
                    leading: TileIcon(Icons.directions_walk, color: worn.isEmpty ? RwColors.accent : RwColors.danger),
                    title: Text(tr('Mijn schoenen')),
                    subtitle: Text(
                      worn.isNotEmpty
                          ? '${worn.first.name} is aan vervanging toe'
                          : d == null
                              ? tr('Houd bij hoeveel km je schoenen hebben')
                              : '${d.name} \u00b7 ${shoeKm(d, runs).round()} km',
                      style: TextStyle(color: worn.isEmpty ? null : RwColors.danger),
                    ),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () => context.go('/me/shoes'),
                  );
                }),
              ],
            ),
          ),
          SizedBox(height: 16),
          _InsightsCard(insights: insights),
          const _SectionTitle('APPARATEN EN KOPPELINGEN'),
          ConnectionsCard(),
          SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: TileIcon(Icons.monitor_heart_outlined),
              title: Text(tr('Hartslagband en loopsensor')),
              subtitle: Text(tr('Live hartslag en zones via Bluetooth')),
              trailing: Icon(Icons.chevron_right),
              onTap: () => openHeartRateScreen(context),
            ),
          ),
          const _SectionTitle('MELDINGEN EN VEILIGHEID'),
          Card(
            child: Column(
              children: [
                ReminderTile(),
                Divider(height: 1, indent: 56),
                RunPauseTile(),
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
                AppearanceTile(),
                Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.help_outline),
                  title: Text(tr('Hulp en veelgestelde vragen')),
                  subtitle: Text(tr('Route op je horloge, batterij, woordenlijst')),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () => openHelp(context),
                ),
                Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.workspace_premium_outlined, color: RwColors.accent),
                  title: Text(tr('Kadans Premium')),
                  subtitle: Text(
                    profile.value?.isPremium ?? false ? tr('Actief') : tr('1 maand gratis, daarna € 5 per maand'),
                  ),
                  trailing: Icon(Icons.chevron_right),
                  onTap: () => context.push('/premium'),
                ),
                Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.favorite_border, color: RwColors.accent),
                  title: Text(tr('Vertel een vriend over Kadans')),
                  subtitle: Text(tr('Stuur een gouden uitnodiging met een link naar de app')),
                  // Luxe kaart met link; zit je in Samen, dan voegt de link je ook meteen als vriend toe.
                  onTap: () async {
                    String? code;
                    try {
                      code = (await ref.read(communityServiceProvider).status()).friendCode;
                    } catch (_) {}
                    final p = ref.read(profileProvider).value;
                    await shareAppInvite(name: p == null || p.displayName == 'loper' ? '' : p.displayName, friendCode: code);
                  },
                ),
                Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.privacy_tip_outlined),
                  title: Text(tr('Privacyverklaring')),
                  onTap: () => openPrivacy(context),
                ),
                Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.download_outlined),
                  title: Text(tr('Mijn gegevens kopiëren')),
                  subtitle: Text(tr('Al je gegevens als tekst (AVG)')),
                  onTap: () => _export(context, ref),
                ),
                Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.logout),
                  title: Text(tr('Uitloggen')),
                  onTap: () async {
                    await OfflineCache.clear();
                    await DiskImageCache.instance.clear();
                    await ref.read(supabaseProvider).auth.signOut();
                  },
                ),
                Divider(height: 1, indent: 56),
                ListTile(
                  leading: TileIcon(Icons.delete_forever_outlined, color: RwColors.danger),
                  title: Text(tr('Account verwijderen'), style: TextStyle(color: RwColors.danger)),
                  onTap: () => _deleteAccount(context, ref),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
          Center(
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: RwColors.subtle, textStyle: TextStyle(fontSize: 12)),
              onPressed: () => openSources(context),
              child: Text(tr('Kadans · bronnen en licenties')),
            ),
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
        title: tr('JOUW LOOPPROFIEL'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nog $left run${left == 1 ? '' : 's'} met weerdata te gaan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(tr('Na 8 runs berekent Kadans bij welke temperatuur en wind jij het snelst loopt. '
              'Tot die tijd gaan we uit van 8–16°C als ideaal.'),
              style: TextStyle(color: RwColors.muted, height: 1.5),
            ),
            SizedBox(height: 12),
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
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(l.$1, color: RwColors.accent, size: 20),
                  SizedBox(width: 12),
                  Expanded(child: Text(l.$2, style: TextStyle(height: 1.45))),
                ],
              ),
            ),
          if (i.buckets.length >= 2) ...[
            SizedBox(height: 8),
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
      height: 128,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var k = 0; k < b.length; k++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Hoeveel sneller dan bij je langzaamste temperatuur.
                    Text(
                      speeds[k] / minS - 1 < 0.005 ? '–' : '+${((speeds[k] / minS - 1) * 100).round()}%',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFeatures: rwTnum,
                          color: speeds[k] == maxS ? RwColors.accent : RwColors.subtle),
                    ),
                    SizedBox(height: 3),
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
                    SizedBox(height: 4),
                    Text('${b[k].from.round()}–${b[k].to.round()}°',
                        maxLines: 1, overflow: TextOverflow.visible, softWrap: false,
                        style: TextStyle(fontSize: 11, color: RwColors.subtle)),
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
        padding: EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Text(tr(text), style: RwText.overline),
      );
}

/// Kiezen hoe zwaar regen meetelt in het advies.
Future<void> _pickRain(BuildContext context, WidgetRef ref) async {
  final current = ref.read(rainPreferenceProvider);
  final picked = await showModalBottomSheet<RainPreference>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(tr('Hoe erg vind je regen?'),
                  style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            for (final r in RainPreference.values)
              ListTile(
                leading: Icon(r == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: r == current ? RwColors.accent : RwColors.subtle),
                title: Text(r.label),
                subtitle: Text(r.explanation),
                selected: r == current,
                onTap: () => Navigator.pop(ctx, r),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(tr('Onweer en gladheid blijven altijd zwaar meetellen.'),
                  style: TextStyle(color: RwColors.subtle, fontSize: 12)),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || picked == current) return;
  HapticFeedback.selectionClick();
  await ref.read(rainPreferenceProvider.notifier).set(picked);
}

/// Eén keuze uit een lijstje (met uitleg per optie), als blad onderin.
Future<void> _pickOption<T>(
  BuildContext context, {
  required String title,
  required List<T> values,
  required T current,
  required String Function(T) label,
  required String Function(T) explanation,
  required void Function(T) onPick,
}) async {
  final picked = await showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(tr(title), style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          for (final v in values)
            ListTile(
              leading: Icon(v == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: v == current ? RwColors.accent : RwColors.subtle),
              title: Text(tr(label(v))),
              subtitle: Text(tr(explanation(v))),
              selected: v == current,
              onTap: () => Navigator.pop(ctx, v),
            ),
        ]),
      ),
    ),
  );
  if (picked == null || picked == current) return;
  HapticFeedback.selectionClick();
  onPick(picked);
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../domain/fit_course.dart';
import '../../domain/geo.dart';
import '../../domain/gpx_parser.dart';
import '../../domain/route_geometry.dart';
import '../../domain/route_turns.dart';
import '../../shared/widgets.dart';

/// Merk van je horloge: bepaalt welk bestand Kadans maakt en welke stappen we uitleggen.
enum WatchBrand { garmin, coros, suunto, polar, amazfit, wearos, none }

extension WatchBrandInfo on WatchBrand {
  String get label => switch (this) {
        WatchBrand.garmin => 'Garmin',
        WatchBrand.coros => 'Coros',
        WatchBrand.suunto => 'Suunto',
        WatchBrand.polar => 'Polar',
        WatchBrand.amazfit => 'Amazfit (Zepp)',
        WatchBrand.wearos => 'Galaxy Watch, Pixel Watch of ander Wear OS',
        WatchBrand.none => 'Geen horloge',
      };

  /// Garmin leest afslagen uit een FIT-koers; de rest werkt met GPX (met afslagen als waypoints).
  bool get usesFit => this == WatchBrand.garmin;

  /// Kan dit horloge zelf een route volgen? Zo niet, dan helpt Kadans via meldingen.
  bool get canImport => this != WatchBrand.wearos && this != WatchBrand.none;

  /// Stappen om de route op het horloge te krijgen.
  List<String> get steps => switch (this) {
        WatchBrand.garmin => const [
            'Tik hieronder op "Zet op mijn horloge" en kies Garmin Connect.',
            'Opent Garmin Connect het bestand niet? Kies dan "Opslaan" en ga in je browser naar Garmin Connect → Training en planning → Koersen → Importeren.',
            'Kies bij de koers "Naar apparaat sturen". Op je horloge: Hardlopen → houd menu ingedrukt → Navigatie → Koersen.',
          ],
        WatchBrand.coros => const [
            'Tik op "Zet op mijn horloge" en kies de COROS-app.',
            'Tik in de COROS-app op Importeren en sla de route op.',
            'Op je horloge: start Hardlopen → Navigatie → kies de route.',
          ],
        WatchBrand.suunto => const [
            'Tik op "Zet op mijn horloge" en kies de Suunto-app.',
            'Sla de route op en zet "Gebruik op horloge" aan.',
            'Op je horloge: start Hardlopen → Navigatie → Routes.',
          ],
        WatchBrand.polar => const [
            'Tik op "Zet op mijn horloge" en kies "Opslaan".',
            'Ga in je browser naar flow.polar.com → Favorieten → Route importeren.',
            'Synchroniseer je horloge. Kies de route bij het starten van een training.',
          ],
        WatchBrand.amazfit => const [
            'Tik op "Zet op mijn horloge" en kies de Zepp-app.',
            'Importeer de route en tik op "Synchroniseren naar apparaat".',
            'Op je horloge: Training → Hardlopen → Route.',
          ],
        WatchBrand.wearos || WatchBrand.none => const [
            'Start de run in Kadans met "Loop deze route" en neem je telefoon mee.',
            'Bij elke afslag zegt Kadans "Over 100 meter rechtsaf" en zie je een grote pijl.',
            'Heb je een horloge? Dan trilt dat ook en zie je de afslag als melding.',
          ],
      };

  /// Website om de route te importeren, als de app dat niet zelf kan.
  String? get importUrl => switch (this) {
        WatchBrand.garmin => 'https://connect.garmin.com/modern/courses',
        WatchBrand.polar => 'https://flow.polar.com/',
        _ => null,
      };
}

const _kBrand = 'watch_brand';

Future<WatchBrand?> loadWatchBrand() async {
  try {
    final p = await SharedPreferences.getInstance();
    final name = p.getString(_kBrand);
    return WatchBrand.values.where((b) => b.name == name).firstOrNull;
  } catch (_) {
    return null;
  }
}

Future<void> saveWatchBrand(WatchBrand b) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBrand, b.name);
  } catch (_) {}
}

/// Kies je horloge (één keer; later te wijzigen).
Future<WatchBrand?> pickWatchBrand(BuildContext context, {WatchBrand? current}) {
  return showModalBottomSheet<WatchBrand>(
    context: context,
    showDragHandle: true,
    backgroundColor: RwColors.surface,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('Welk horloge heb je?', style: RwText.title),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('Dan maakt Kadans het juiste bestand en leggen we precies uit wat je moet doen.',
                  style: TextStyle(color: RwColors.muted, height: 1.4)),
            ),
            for (final b in WatchBrand.values)
              ListTile(
                leading: Icon(b == WatchBrand.none ? Icons.phone_android : Icons.watch_outlined,
                    color: b == current ? RwColors.accent : RwColors.muted),
                title: Text(b.label),
                trailing: b == current ? Icon(Icons.check, color: RwColors.accent) : null,
                onTap: () => Navigator.pop(ctx, b),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Het bestand voor jouw horloge: FIT voor Garmin, anders GPX. Beide met de afslagen erin.
({Uint8List bytes, String fileName, String mime}) watchFile(RunRoute r, WatchBrand brand, {List<RouteTurn>? turns}) {
  final pts = decodePolyline(r.polyline);
  final t = turns ?? detectTurns(RouteTrack(pts));
  final safe = r.name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim().replaceAll(' ', '-');
  final base = safe.isEmpty ? 'route' : safe;
  if (brand.usesFit) {
    final pace = r.estimatedDurationSeconds != null && r.distanceMeters > 0
        ? r.estimatedDurationSeconds! / (r.distanceMeters / 1000)
        : 360.0;
    return (
      bytes: buildFitCourse(r.name, pts, turns: t, profile: r.profileOrKmPoints, paceSecondsPerKm: pace),
      fileName: '$base.fit',
      mime: 'application/octet-stream',
    );
  }
  return (
    bytes: Uint8List.fromList(utf8.encode(buildGpx(r.name, pts, profile: r.profileOrKmPoints, turns: t))),
    fileName: '$base.gpx',
    mime: 'application/gpx+xml',
  );
}

/// "Route naar je horloge": kiest het juiste bestand en legt de stappen voor jouw merk uit.
/// [onRunWithPhone] start de run met deze route (voor horloges zonder route-import).
Future<void> sendRouteToWatch(BuildContext context, RunRoute r, {VoidCallback? onRunWithPhone}) async {
  var brand = await loadWatchBrand();
  if (!context.mounted) return;
  if (brand == null) {
    brand = await pickWatchBrand(context);
    if (brand == null || !context.mounted) return;
    await saveWatchBrand(brand);
    if (!context.mounted) return;
  }
  final turns = detectTurns(RouteTrack(decodePolyline(r.polyline)));
  WatchBrand current = brand;
  final runWithPhone = onRunWithPhone;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: RwColors.surface,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Route naar je horloge', style: RwText.title),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.watch_outlined, size: 18, color: RwColors.muted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(current.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                  TextButton(
                    onPressed: () async {
                      final b = await pickWatchBrand(ctx, current: current);
                      if (b == null) return;
                      await saveWatchBrand(b);
                      setSheet(() => current = b);
                    },
                    child: const Text('Wijzig'),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: RwColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.turn_right, color: RwColors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        turns.isEmpty
                            ? 'Geen afslagen gevonden: deze route is vooral rechtdoor.'
                            : current.canImport
                                ? '${turns.length} afslagen herkend. ${current.usesFit ? 'Je horloge trilt vóór elke afslag en toont de richting.' : 'Ze staan als punten in het bestand.'}'
                                : '${turns.length} afslagen herkend. Kadans meldt ze tijdens het lopen.',
                        style: const TextStyle(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < current.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: RwColors.surfaceHigh,
                        child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(current.steps[i], style: TextStyle(color: RwColors.muted, height: 1.45))),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              if (current.canImport)
                FilledButton.icon(
                  onPressed: () => _share(ctx, r, current, turns),
                  icon: const Icon(Icons.watch),
                  label: const Text('Zet op mijn horloge'),
                )
              else
                FilledButton.icon(
                  onPressed: runWithPhone == null
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          runWithPhone();
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Loop deze route'),
                ),
              if (current.importUrl != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(current.importUrl!), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new),
                  label: Text('${current == WatchBrand.garmin ? 'Garmin-koersen' : 'Polar Flow'} openen'),
                ),
              ],
              if (current.canImport) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => _share(ctx, r, current == WatchBrand.garmin ? WatchBrand.coros : WatchBrand.garmin, turns),
                  child: Text(current.usesFit ? 'Liever een GPX-bestand' : 'Liever een FIT-bestand (Garmin, Wahoo)'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _share(BuildContext context, RunRoute r, WatchBrand brand, List<RouteTurn> turns) async {
  try {
    final f = watchFile(r, brand, turns: turns);
    final res = await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(f.bytes, mimeType: f.mime, name: f.fileName)],
      subject: r.name,
    ));
    if (res.status == ShareResultStatus.dismissed || !context.mounted) return;
    await _askIfItArrived(context, brand);
  } catch (_) {
    if (context.mounted) showMessage(context, 'Het bestand kon niet worden gemaakt of gedeeld.', error: true);
  }
}

const _kChecks = 'watch_check_count';

/// Wat je kunt proberen als de route niet op je horloge verschijnt.
List<String> watchTroubleshooting(WatchBrand b) => [
      ...switch (b) {
        WatchBrand.garmin => const [
            'Open Garmin Connect en kijk bij Meer → Training en planning → Koersen. Staat hij daar, tik dan op "Naar apparaat sturen".',
            'Synchroniseer je horloge: trek in Garmin Connect het beginscherm omlaag.',
            'Zag je Garmin Connect niet bij het delen? Kies "Opslaan" en importeer het bestand op connect.garmin.com → Koersen.',
          ],
        WatchBrand.coros => const [
            'Open de COROS-app → Profiel → Routes. Staat hij daar niet, tik dan op Importeren en kies het bestand.',
            'Zet bij de route "Synchroniseren met horloge" aan en houd je horloge vlakbij je telefoon.',
          ],
        WatchBrand.suunto => const [
            'Open de Suunto-app → Kaart → Mijn routes en zet "Gebruik op horloge" aan.',
            'Synchroniseer je horloge (Suunto-app → je horloge → Synchroniseren).',
          ],
        WatchBrand.polar => const [
            'Polar kan het bestand niet uit een andere app openen: importeer het op flow.polar.com → Favorieten.',
            'Zet de route bij Favorieten en synchroniseer daarna je horloge met Polar Flow.',
          ],
        WatchBrand.amazfit => const [
            'Open de Zepp-app → Profiel → je horloge → Route-bestanden en tik op Synchroniseren.',
            'Lukt het niet, kies dan bij het delen eerst "Opslaan" en importeer het bestand in de Zepp-app.',
          ],
        WatchBrand.wearos || WatchBrand.none => const [
            'Je horloge laat Kadans-meldingen zien: zet meldingen van Kadans aan in de Galaxy Wearable- of Pixel Watch-app.',
          ],
      },
      'Probeer het andere bestandstype (GPX of FIT) via de knop onderaan.',
      'Lukt het nog niet? Loop de route met je telefoon: Kadans zegt elke afslag en je horloge trilt mee.',
    ];

/// Na het versturen: staat de route erop? Zo niet, laat zien wat je kunt doen. Vraagt het de eerste 3 keer.
Future<void> _askIfItArrived(BuildContext context, WatchBrand brand) async {
  var count = 0;
  try {
    final p = await SharedPreferences.getInstance();
    count = p.getInt(_kChecks) ?? 0;
    if (count >= 3) return;
    await p.setInt(_kChecks, count + 1);
  } catch (_) {}
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Staat de route op je horloge?'),
      content: const Text('Het kan een halve minuut duren voordat je horloge gesynchroniseerd is.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nee, lukt niet')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ja, top')),
      ],
    ),
  );
  if (ok != false || !context.mounted) return;
  final tips = watchTroubleshooting(brand);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: RwColors.surface,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Zo krijg je hem op je ${brand.label}', style: RwText.title),
            const SizedBox(height: 12),
            for (var i = 0; i < tips.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: RwColors.surfaceHigh,
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tips[i], style: TextStyle(color: RwColors.muted, height: 1.45))),
                ]),
              ),
            if (brand.importUrl != null)
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(brand.importUrl!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: Text(brand == WatchBrand.garmin ? 'Garmin-koersen openen' : 'Polar Flow openen'),
              ),
            const SizedBox(height: 6),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Begrepen')),
          ],
        ),
      ),
    ),
  );
}


/// Een loopmaatje uitnodigen: tekst met het beste moment en de route als GPX erbij.
Future<void> inviteRunBuddy(BuildContext context, RunRoute r, {DateTime? when, String? weather}) async {
  try {
    final pts = decodePolyline(r.polyline);
    final gpx = buildGpx(r.name, pts, profile: r.profileOrKmPoints, turns: detectTurns(RouteTrack(pts)));
    final now = DateTime.now();
    String moment(DateTime t) {
      final day = t.day == now.day && t.month == now.month
          ? 'vandaag'
          : (t.difference(DateTime(now.year, now.month, now.day)).inDays == 1 ? 'morgen' : _weekday(t));
      final hh = t.hour.toString().padLeft(2, '0'), mm = t.minute.toString().padLeft(2, '0');
      return '$day om $hh:$mm';
    }

    final km = (r.distanceMeters / 1000).toStringAsFixed(1).replaceAll('.', ',');
    final text = [
      'Zin om mee te lopen? 🏃',
      if (when != null) 'Beste moment volgens Kadans: ${moment(when)}${weather == null ? '' : ' ($weather)'}.',
      'Route: ${r.name}, $km km. Het routebestand zit erbij (open het in je horloge-app of in Komoot).',
      'Start: https://www.google.com/maps/search/?api=1&query=${r.startLatitude.toStringAsFixed(5)},${r.startLongitude.toStringAsFixed(5)}',
    ].join('\n');
    final safe = r.name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim().replaceAll(' ', '-');
    await SharePlus.instance.share(ShareParams(
      text: text,
      subject: 'Samen lopen: ${r.name}',
      files: [XFile.fromData(Uint8List.fromList(utf8.encode(gpx)), mimeType: 'application/gpx+xml', name: '${safe.isEmpty ? 'route' : safe}.gpx')],
    ));
  } catch (_) {
    if (context.mounted) showMessage(context, 'Uitnodigen is niet gelukt. Probeer het opnieuw.', error: true);
  }
}

String _weekday(DateTime t) => const ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'][t.weekday - 1];

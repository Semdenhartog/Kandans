// Wedstrijden in de buurt: veegrij in Samen, overzicht met filters en detail met luchtfoto van de start.
// Data: tabel race_calendar (officiële bekendmakingen van gemeenten, open data CC-0).
// Beeld: PDOK-luchtfoto (Beeldmateriaal Nederland, open data) van de startplek; zonder plek een eigen sfeerfoto.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/services/race_calendar_service.dart';
import '../../domain/race_calendar.dart';
import '../../shared/widgets.dart';
import '../races/add_race_screen.dart';

String _loc() => LanguageController.instance.lang.intlLocale;

const _ink = Color(0xFF1A1410);
const _gold = Color(0xFFD9BF92);

String raceKindLabel(RaceKind k) => switch (k) {
      RaceKind.marathon => tr('Marathon'),
      RaceKind.halve => tr('Halve marathon'),
      RaceKind.trail => tr('Trail'),
      RaceKind.cross => tr('Cross'),
      RaceKind.estafette => tr('Estafette'),
      RaceKind.loop => tr('Loop'),
    };

String raceStatusLabel(RaceStatus s) => switch (s) {
      RaceStatus.verleend => tr('Vergunning verleend'),
      RaceStatus.melding => tr('Gemeld bij gemeente'),
      RaceStatus.aangevraagd => tr('Vergunning aangevraagd'),
    };

String _kmLabel(double? km) =>
    km == null ? '' : trf('{km} km van je', {'km': km < 10 ? km.toStringAsFixed(1).replaceAll('.', ',') : '${km.round()}'});

// ---------------------------------------------------------------- luchtfoto

const _photoTiles = 'https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0/Actueel_orthoHR/EPSG:3857';

/// Luchtfoto rond een punt (enkele PDOK-tegels, gecentreerd), met een eigen sfeerfoto eronder als
/// terugval (offline of buiten Nederland). Donker verloop onderaan voor leesbare tekst.
class AerialHeader extends StatelessWidget {
  const AerialHeader({super.key, required this.lat, required this.lon, this.kind = RaceKind.loop, this.zoom = 16, this.credit = false});
  final double? lat, lon;
  final RaceKind kind;
  final int zoom;
  final bool credit;

  String get _fallback => switch (kind) {
        RaceKind.cross || RaceKind.trail => 'assets/foto/mist.jpg',
        _ => 'assets/foto/heide.jpg',
      };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final tiles = <Widget>[];
      if (lat != null && lon != null && w.isFinite && h.isFinite) {
        final t = webMercatorTile(lat!, lon!, zoom);
        final size = math.max(w, h) / 1.4; // ±1,4 tegel over de breedte: de omgeving van de start
        final cx = (t.x + t.fx) * size, cy = (t.y + t.fy) * size;
        final left = cx - w / 2, top = cy - h / 2;
        for (var ty = (top / size).floor(); ty * size < top + h; ty++) {
          for (var tx = (left / size).floor(); tx * size < left + w; tx++) {
            tiles.add(Positioned(
              left: tx * size - left,
              top: ty * size - top,
              width: size + 0.5,
              height: size + 0.5,
              child: Image.network(
                '$_photoTiles/$zoom/$tx/$ty.jpeg',
                fit: BoxFit.fill,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ));
          }
        }
      }
      return Stack(fit: StackFit.expand, clipBehavior: Clip.hardEdge, children: [
        Image.asset(_fallback, fit: BoxFit.cover),
        ...tiles,
        // Warm, donker verloop: luxe en leesbaar.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0x00000000), Color(0xCC1A1410)],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
        if (credit && lat != null)
          const Positioned(
            right: 8,
            bottom: 4,
            child: Text('Luchtfoto © Beeldmateriaal Nederland', style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 9.5)),
          ),
      ]);
    });
  }
}

// ---------------------------------------------------------------- kaart

class _DateBadge extends StatelessWidget {
  const _DateBadge(this.date);
  final DateTime date;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: _ink.withValues(alpha: 0.82), borderRadius: BorderRadius.circular(RwRadius.s)),
        child: Text(
          DateFormat('d MMM y', _loc()).format(date).replaceAll('.', '').toUpperCase(),
          style: SectionLabel.style(color: _gold).copyWith(fontWeight: FontWeight.w700, fontSize: 11.5),
        ),
      );
}

class _KindTag extends StatelessWidget {
  const _KindTag(this.kind);
  final RaceKind kind;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(RwRadius.s)),
        child: Text(raceKindLabel(kind).toUpperCase(), style: SectionLabel.style(color: _ink).copyWith(fontWeight: FontWeight.w700, fontSize: 10.5)),
      );
}

class _StatusDot extends StatelessWidget {
  const _StatusDot(this.status);
  final RaceStatus status;
  @override
  Widget build(BuildContext context) {
    final c = status == RaceStatus.verleend ? RwColors.good : (status == RaceStatus.melding ? RwColors.accent : RwColors.subtle);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(raceStatusLabel(status), style: TextStyle(color: RwColors.muted, fontSize: 12.5)),
    ]);
  }
}

/// Kaart met luchtfoto-header, datum in goud, soort, naam, plaats en afstand.
class RaceCard extends StatelessWidget {
  const RaceCard({super.key, required this.race, this.km, this.onTap, this.headerHeight = 124});
  final RaceListing race;
  final double? km;
  final VoidCallback? onTap;
  final double headerHeight;

  @override
  Widget build(BuildContext context) {
    final where = [race.where, if (km != null) _kmLabel(km)].where((x) => x.isNotEmpty).join(' · ');
    return Material(
      color: RwColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RwRadius.l), side: BorderSide(color: RwColors.hairline)),
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: headerHeight,
            child: Stack(fit: StackFit.expand, children: [
              AerialHeader(lat: race.lat, lon: race.lon, kind: race.kind),
              Positioned(top: 10, right: 10, child: _DateBadge(race.date)),
              Positioned(left: 12, bottom: 10, child: _KindTag(race.kind)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(race.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 18, color: RwColors.text, height: 1.15)),
              if (where.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.place_outlined, size: 15, color: RwColors.accent),
                  const SizedBox(width: 4),
                  Expanded(child: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: RwColors.muted))),
                ]),
              ],
              const SizedBox(height: 6),
              _StatusDot(race.status),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- rij in Samen

/// Hoe ver we standaard zoeken in de rij; is er niets binnen die straal, dan de eerstvolgende in Nederland.
const _nearKm = 60.0;

class RacesStrip extends ConsumerWidget {
  const RacesStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(raceCalendarProvider).value;
    if (state == null || state.races.isEmpty) return const SizedBox.shrink();
    var list = racesNear(state.races, lat: state.lat, lon: state.lon, maxKm: state.lat == null ? null : _nearKm);
    var nearby = state.lat != null;
    if (list.isEmpty) {
      list = racesNear(state.races);
      nearby = false;
    }
    list = list.take(8).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: SectionLabel(nearby ? tr('Wedstrijden in de buurt') : tr('Wedstrijden in Nederland'))),
        TextButton(
          onPressed: () => openRaceCalendar(context),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: Text(tr('Alles bekijken')),
        ),
      ]),
      SizedBox(
        height: 236,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => SizedBox(
            width: 292,
            child: RaceCard(
              race: list[i],
              km: list[i].kmFrom(state.lat, state.lon),
              onTap: () => openRace(context, list[i], list[i].kmFrom(state.lat, state.lon)),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- overzicht

Future<void> openRaceCalendar(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RaceCalendarScreen()));

Future<void> openRace(BuildContext context, RaceListing race, double? km) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RaceDetailScreen(race: race, km: km)));

class RaceCalendarScreen extends ConsumerStatefulWidget {
  const RaceCalendarScreen({super.key});
  @override
  ConsumerState<RaceCalendarScreen> createState() => _RaceCalendarScreenState();
}

class _RaceCalendarScreenState extends ConsumerState<RaceCalendarScreen> {
  double? _km = 50; // null = heel Nederland
  RaceKind? _kind;

  static const _radii = <double?>[25, 50, 100, null];

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(raceCalendarProvider);
    final state = async.value;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Wedstrijdkalender'))),
      body: state == null
          ? (async.hasError
              ? ErrorView(message: '${async.error}', onRetry: () => ref.invalidate(raceCalendarProvider))
              : LoadingView(cards: 3))
          : RefreshIndicator(
              onRefresh: () async {
                await ref.read(raceCalendarServiceProvider).upcoming(force: true);
                ref.invalidate(raceCalendarProvider);
                await ref.read(raceCalendarProvider.future);
              },
              child: _body(state),
            ),
    );
  }

  Widget _body(RaceCalendarState state) {
    final hasPlace = state.lat != null;
    final races = racesNear(
      state.races,
      lat: state.lat,
      lon: state.lon,
      maxKm: hasPlace ? _km : null,
      kinds: _kind == null ? null : {_kind!},
    );
    // Per maand groeperen.
    final items = <Object>[];
    String? month;
    for (final r in races) {
      final m = DateFormat('MMMM y', _loc()).format(r.date).toUpperCase();
      if (m != month) items.add(month = m);
      items.add(r);
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: items.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (hasPlace) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in _radii)
                  ChoiceChip(
                    label: Text(r == null ? tr('Heel Nederland') : trf('{km} km', {'km': '${r.round()}'})),
                    selected: _km == r,
                    onSelected: (_) => setState(() => _km = r),
                  ),
              ]),
              const SizedBox(height: 8),
            ],
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final k in <RaceKind?>[null, RaceKind.loop, RaceKind.halve, RaceKind.marathon, RaceKind.trail, RaceKind.cross])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(k == null ? tr('Alle') : raceKindLabel(k)),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            if (races.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: EmptyState(
                  icon: Icons.emoji_events_outlined,
                  title: tr('Geen wedstrijden gevonden'),
                  message: tr('Kies een grotere afstand of een andere soort.'),
                ),
              ),
          ]);
        }
        if (i == items.length + 1) {
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(
              tr('Bron: officiële bekendmakingen van gemeenten (open data). Kijk voor inschrijven en afstanden altijd op de site van de organisatie.'),
              style: TextStyle(color: RwColors.subtle, fontSize: 12.5, height: 1.4),
            ),
          );
        }
        final it = items[i - 1];
        if (it is String) {
          return Padding(padding: const EdgeInsets.only(top: 18, bottom: 8), child: SectionLabel(it));
        }
        final r = it as RaceListing;
        final km = r.kmFrom(state.lat, state.lon);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RaceCard(race: r, km: km, headerHeight: 132, onTap: () => openRace(context, r, km)),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- detail

class RaceDetailScreen extends StatelessWidget {
  const RaceDetailScreen({super.key, required this.race, this.km});
  final RaceListing race;
  final double? km;

  @override
  Widget build(BuildContext context) {
    final r = race;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          foregroundColor: Colors.white,
          backgroundColor: _ink,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              AerialHeader(lat: r.lat, lon: r.lon, kind: r.kind, zoom: 15, credit: true),
              Positioned(
                left: 20,
                right: 20,
                bottom: 22,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _KindTag(r.kind),
                  const SizedBox(height: 10),
                  Text(r.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 30, height: 1.05, color: Colors.white)),
                ]),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          sliver: SliverList.list(children: [
            _Fact(icon: Icons.event_outlined, title: Fmt.dateLong(r.date), sub: DateFormat('EEEE', _loc()).format(r.date)),
            if (r.where.isNotEmpty)
              _Fact(
                icon: Icons.place_outlined,
                title: r.where,
                sub: [if (r.municipality != null && r.municipality != r.where) trf('Gemeente {g}', {'g': r.municipality!}), if (km != null) _kmLabel(km)].join(' · '),
              ),
            _Fact(
              icon: Icons.verified_outlined,
              title: raceStatusLabel(r.status),
              sub: r.status == RaceStatus.verleend
                  ? tr('De gemeente heeft toestemming gegeven.')
                  : tr('Nog niet definitief: de gemeente moet nog beslissen.'),
            ),
            const SizedBox(height: 18),
            KadansButton(
              label: tr('Zet in Mijn wedstrijden'),
              icon: Icons.flag_outlined,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => AddRaceScreen(
                  initialName: r.name,
                  initialDate: r.date,
                  initialKm: r.typicalMeters / 1000,
                  startLatitude: r.lat,
                  startLongitude: r.lon,
                ),
              )),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://www.google.com/search?q=${Uri.encodeQueryComponent('${r.name} ${r.date.year} inschrijven')}'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.search, size: 18),
              label: Text(tr('Zoek inschrijving en afstanden')),
            ),
            if (Uri.tryParse(r.sourceUrl)?.hasScheme ?? false)
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(r.sourceUrl), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.gavel_outlined, size: 18),
                label: Text(tr('Officiële bekendmaking bekijken')),
              ),
            const SizedBox(height: 16),
            Text(
              tr('Gevonden in de officiële bekendmakingen van de gemeente (open data). Datum en plaats komen uit de vergunning; controleer ze op de site van de organisatie.'),
              style: TextStyle(color: RwColors.subtle, fontSize: 12.5, height: 1.4),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.title, this.sub = ''});
  final IconData icon;
  final String title, sub;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: RwColors.surface, borderRadius: BorderRadius.circular(RwRadius.s), border: Border.all(color: RwColors.hairline)),
            child: Icon(icon, size: 20, color: RwColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: RwColors.text)),
              if (sub.isNotEmpty) Text(sub, style: TextStyle(color: RwColors.muted, fontSize: 13)),
            ]),
          ),
        ]),
      );
}

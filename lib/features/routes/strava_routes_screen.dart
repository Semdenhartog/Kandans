import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/sync_service.dart';
import '../../shared/widgets.dart';
import 'poster_design.dart' show PosterRoutePainter;
import '../../domain/geo.dart';

const _stravaOrange = Color(0xFFFC5200);

/// Opent "routes uit Strava importeren".
void openStravaRoutes(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StravaRoutesScreen()));

final stravaRoutesProvider = FutureProvider.autoDispose<StravaRouteList>((ref) => ref.read(syncServiceProvider).stravaRoutes());

/// Kies welke van je Strava-routes je in Kadans wilt hebben.
class StravaRoutesScreen extends ConsumerStatefulWidget {
  const StravaRoutesScreen({super.key});

  @override
  ConsumerState<StravaRoutesScreen> createState() => _StravaRoutesScreenState();
}

class _StravaRoutesScreenState extends ConsumerState<StravaRoutesScreen> {
  final _picked = <String>{};
  bool _busy = false;
  int _done = 0;

  Future<void> _import(List<StravaRouteSummary> chosen) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _done = 0;
    });
    final sync = ref.read(syncServiceProvider);
    final failed = <String>[];
    for (final r in chosen) {
      try {
        await sync.importStravaRoute(r);
      } catch (_) {
        failed.add(r.name);
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    ref.invalidate(routesProvider);
    // Je runs van die routes meteen koppelen.
    await sync.autoLinkRuns().catchError((Object _) => 0);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _picked.clear();
    });
    final ok = chosen.length - failed.length;
    showMessage(
      context,
      failed.isEmpty
          ? '$ok ${ok == 1 ? 'route' : 'routes'} geïmporteerd.'
          : '$ok geïmporteerd. Niet gelukt: ${failed.take(3).join(', ')}${failed.length > 3 ? '…' : ''}',
      error: failed.isNotEmpty && ok == 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(stravaRoutesProvider);
    final have = {
      for (final r in ref.watch(routesProvider).value ?? const <RunRoute>[])
        if (r.stravaRouteId != null) r.stravaRouteId!,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Routes uit Strava')),
      body: list.when(
        loading: () => const LoadingView(cards: 4),
        error: (e, _) => ErrorView(message: friendlyError(e), onRetry: () => ref.invalidate(stravaRoutesProvider)),
        data: (data) {
          final available = [for (final r in data.routes) if (!have.contains(r.id)) r];
          final chosen = [for (final r in data.routes) if (_picked.contains(r.id)) r];
          return Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (!data.canSeePrivate) _PrivateHint(onReconnect: () => ref.read(syncServiceProvider).connectStrava()),
                  if (data.routes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: EmptyState(
                        icon: Icons.route_outlined,
                        title: 'Geen hardlooproutes gevonden',
                        message: 'Maak in Strava een route voor hardlopen, of sla er een op. Dan staat hij hier.',
                      ),
                    )
                  else ...[
                    Row(children: [
                      Expanded(
                        child: Text('${data.routes.length} ${data.routes.length == 1 ? 'route' : 'routes'} in Strava',
                            style: const TextStyle(color: RwColors.muted)),
                      ),
                      if (available.isNotEmpty)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    if (_picked.length == available.length) {
                                      _picked.clear();
                                    } else {
                                      _picked.addAll(available.map((r) => r.id));
                                    }
                                  }),
                          child: Text(_picked.length == available.length ? 'Niets kiezen' : 'Alles kiezen'),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    for (final r in data.routes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RouteTile(
                          route: r,
                          imported: have.contains(r.id),
                          picked: _picked.contains(r.id),
                          onTap: _busy || have.contains(r.id)
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    if (!_picked.remove(r.id)) _picked.add(r.id);
                                  });
                                },
                        ),
                      ),
                    if (data.cyclingSkipped > 0)
                      Text('${data.cyclingSkipped} fietsroutes overgeslagen.',
                          textAlign: TextAlign.center, style: const TextStyle(color: RwColors.subtle, fontSize: 12)),
                    const SizedBox(height: 6),
                    const Text('Routes via Strava. Ontkoppel je Strava, dan verdwijnen ze weer uit Kadans.',
                        textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 11)),
                  ],
                ],
              ),
            ),
            if (chosen.isNotEmpty || _busy)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _stravaOrange, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52)),
                    onPressed: _busy ? null : () => _import(chosen),
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download),
                    label: Text(_busy ? 'Importeren… $_done van ${chosen.isEmpty ? _done : chosen.length}' : 'Importeer ${chosen.length} ${chosen.length == 1 ? 'route' : 'routes'}'),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class _PrivateHint extends StatelessWidget {
  const _PrivateHint({required this.onReconnect});
  final Future<void> Function() onReconnect;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _stravaOrange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _stravaOrange.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Zie je je privéroutes niet?', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Je koppeling is van vóór deze versie. Koppel Strava opnieuw en geef toestemming voor privéroutes.',
              style: TextStyle(color: RwColors.muted, height: 1.4)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onReconnect, child: const Text('Opnieuw koppelen', style: TextStyle(color: _stravaOrange))),
          ),
        ]),
      );
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({required this.route, required this.imported, required this.picked, required this.onTap});
  final StravaRouteSummary route;
  final bool imported;
  final bool picked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pts = decodePolyline(route.summaryPolyline);
    return Semantics(
      button: !imported,
      selected: picked,
      label: '${route.name}, ${Fmt.km(route.distanceMeters, decimals: 1)}${imported ? ', al geïmporteerd' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: picked ? _stravaOrange.withValues(alpha: 0.10) : RwColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: picked ? _stravaOrange : RwColors.border, width: picked ? 1.5 : 1),
          ),
          child: Row(children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: RwColors.surfaceHigh, borderRadius: BorderRadius.circular(12)),
              child: CustomPaint(painter: PosterRoutePainter(pts, color: imported ? RwColors.subtle : RwColors.accent, width: 2.5)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (route.starred) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.star, size: 14, color: RwColors.warning)),
                  Expanded(
                    child: Text(route.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(
                  [
                    Fmt.km(route.distanceMeters, decimals: 1),
                    if (route.elevationGainMeters != null) '${route.elevationGainMeters!.round()} m omhoog',
                    if (route.isPrivate) 'privé',
                  ].join(' · '),
                  style: const TextStyle(color: RwColors.subtle, fontSize: 12),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            imported
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle, size: 18, color: RwColors.good),
                    SizedBox(width: 4),
                    Text('In Kadans', style: TextStyle(color: RwColors.good, fontSize: 12)),
                  ])
                : Icon(picked ? Icons.check_circle : Icons.radio_button_unchecked, color: picked ? _stravaOrange : RwColors.subtle),
          ]),
        ),
      ),
    );
  }
}

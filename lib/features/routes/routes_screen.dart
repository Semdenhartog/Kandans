import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../data/services/sync_service.dart';
import '../../domain/gpx_parser.dart';
import '../../shared/widgets.dart';
import '../dashboard/dashboard_providers.dart';
import 'route_shape.dart';

class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  bool _importing = false;

  /// Gemiddeld tempo van recente runs, voor de geschatte duur van een route.
  double _typicalPace() {
    final runs = ref.read(activitiesProvider).when(
          data: (a) => a,
          loading: () => const <Activity>[],
          error: (_, _) => const <Activity>[],
        );
    final recent = runs.take(10).where((a) => a.paceSecondsPerKm > 0).toList();
    if (recent.isEmpty) return 360;
    return recent.fold<double>(0, (s, a) => s + a.paceSecondsPerKm) / recent.length;
  }

  Future<void> _importGpx() async {
    setState(() => _importing = true);
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null) return;
      if (!file.name.toLowerCase().endsWith('.gpx')) {
        throw GpxParseException('Kies een .gpx-bestand.');
      }
      final bytes = await file.readAsBytes();
      final route = parseGpx(
        utf8.decode(bytes, allowMalformed: true),
        fallbackName: file.name.replaceAll(RegExp(r'\.gpx$', caseSensitive: false), ''),
        estimatedPaceSecPerKm: _typicalPace(),
      );
      final id = await ref.read(repositoryProvider).addRoute(route);
      ref.invalidate(routesProvider);
      final linked = await ref.read(syncServiceProvider).autoLinkRuns().catchError((_) => 0);
      if (!mounted) return;
      showMessage(
        context,
        'Route "${route.name}" toegevoegd (${Fmt.km(route.distanceMeters, decimals: 1)}).'
        '${linked > 0 ? ' $linked eerdere ${linked == 1 ? 'run' : 'runs'} op deze route gekoppeld.' : ''}',
      );
      context.go('/routes/$id');
    } on GpxParseException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(routesProvider);
    final bests = ref.watch(routeBestProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mijn routes'),
        actions: [
          IconButton(
            tooltip: 'Zelf een route tekenen',
            onPressed: () => context.go('/routes/tekenen'),
            icon: const Icon(Icons.draw_outlined),
          ),
          IconButton(
            tooltip: 'GPX importeren',
            onPressed: _importing ? null : _importGpx,
            icon: _importing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'route-maken',
        onPressed: () => context.go('/routes/maken'),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Route maken'),
      ),
      body: routes.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(routesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.route_outlined,
              title: 'Nog geen routes',
              message: 'Laat RunWise een rondje maken vanaf je huis of een adres, op de afstand of tijd die jij wilt. '
                  'Of teken zelf een route (potloodje rechtsboven) of importeer een GPX-bestand van je vaste rondje.',
              actionLabel: 'Route maken',
              onAction: () => context.go('/routes/maken'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r = list[i];
              return RwCard(
                onTap: () => context.go('/routes/${r.id}'),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: RouteShape(polyline: r.polyline, strokeWidth: 2),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (r.isFavorite)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.star, size: 16, color: RwColors.accent),
                                ),
                              Expanded(
                                child: Text(
                                  r.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              Fmt.km(r.distanceMeters, decimals: 1),
                              if (r.elevationGainMeters != null) '${r.elevationGainMeters!.round()} hm',
                              r.sourceLabel,
                            ].join(' · '),
                            style: const TextStyle(color: RwColors.subtle),
                          ),
                          if (bests[r.id] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Beste moment: ${Fmt.time(bests[r.id]!.start)} · score ${bests[r.id]!.score}',
                              style: const TextStyle(color: RwColors.accent, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: RwColors.subtle),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

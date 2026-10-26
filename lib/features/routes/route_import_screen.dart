import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/geo.dart';
import '../../domain/gpx_parser.dart';
import '../../domain/route_share.dart';
import '../../shared/widgets.dart';
import 'route_shape.dart';

/// Een route die iemand met je deelde (via een link): bekijken en opslaan in je eigen routes.
class RouteImportScreen extends ConsumerStatefulWidget {
  const RouteImportScreen({super.key, required this.params});
  final Map<String, String> params;

  @override
  ConsumerState<RouteImportScreen> createState() => _RouteImportScreenState();
}

class _RouteImportScreenState extends ConsumerState<RouteImportScreen> {
  bool _saving = false;

  Future<void> _save(SharedRoute shared) async {
    setState(() => _saving = true);
    try {
      // Via GPX, zodat afstand, punten en duur op dezelfde manier worden berekend als bij een import.
      final route = parseGpx(buildGpx(shared.name, shared.points), fallbackName: shared.name);
      final id = await ref.read(repositoryProvider).addRoute(route);
      ref.invalidate(routesProvider);
      if (!mounted) return;
      showMessage(context, '${shared.name} staat in je routes.');
      context.go('/routes/$id');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shared = SharedRoute.fromParams(widget.params);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gedeelde route'),
        leading: Navigator.of(context).canPop()
            ? null
            : IconButton(icon: const Icon(Icons.close), tooltip: 'Sluiten', onPressed: () => context.go('/routes')),
      ),
      body: shared == null
          ? const EmptyState(
              icon: Icons.link_off,
              title: 'Deze link werkt niet',
              message: 'Er zit geen route in deze link. Vraag of iemand hem opnieuw deelt.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(shared.name, style: RwText.title),
                const SizedBox(height: 4),
                Text(
                  '${Fmt.km(_length(shared.points), decimals: 1)} · iemand deelde deze route met je',
                  style: TextStyle(color: RwColors.subtle),
                ),
                const SizedBox(height: 16),
                RwCard(
                  child: AspectRatio(
                    aspectRatio: 1.2,
                    child: RouteShape(polyline: encodePolyline(shared.points), strokeWidth: 4),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: _saving ? null : () => _save(shared),
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Opslaan in mijn routes'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Daarna zie je het beste moment, de wind op de route en kun je hem naar je horloge sturen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: RwColors.muted, fontSize: 13),
                ),
              ],
            ),
    );
  }

  static double _length(List<LatLng> pts) {
    var m = 0.0;
    for (var i = 1; i < pts.length; i++) {
      m += distanceMeters(pts[i - 1], pts[i]);
    }
    return m;
  }
}

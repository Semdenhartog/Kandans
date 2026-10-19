import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/format.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../domain/geo.dart';
import '../../domain/route_geometry.dart';
import '../../shared/widgets.dart';
import 'elevation_profile.dart';
import 'route_map.dart';

/// Alles wat nodig is om een route groot te tonen.
class RouteMapData {
  const RouteMapData({
    required this.title,
    required this.polyline,
    required this.distanceMeters,
    this.windSpeedKmh,
    this.windFromDegrees,
    this.reversed = false,
    this.profile = const [],
  });

  final String title;
  final String polyline;
  final double distanceMeters;
  final double? windSpeedKmh;
  final double? windFromDegrees;
  final bool reversed;

  /// Al in de getoonde looprichting.
  final List<ElevationSample> profile;
}

void openRouteMap(BuildContext context, RouteMapData data) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => RouteMapScreen(data: data),
  ));
}

/// Kaart op volledig scherm, met je eigen locatie en het hoogteprofiel.
class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({super.key, required this.data});
  final RouteMapData data;

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final _controller = MapController();
  final _highlight = ValueNotifier<double?>(null);
  bool _locating = false;
  bool _showMe = false;

  @override
  void initState() {
    super.initState();
    _checkLocation();
  }

  @override
  void dispose() {
    _highlight.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Toon je locatie meteen als je daar al eerder toestemming voor gaf.
  Future<void> _checkLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (mounted && (perm == LocationPermission.always || perm == LocationPermission.whileInUse)) {
        setState(() => _showMe = true);
      }
    } catch (_) {}
  }

  void _fitRoute() {
    final pts = [for (final p in decodePolyline(widget.data.polyline)) ll.LatLng(p.lat, p.lon)];
    if (pts.length < 2) return;
    _controller.fitCamera(CameraFit.coordinates(
      coordinates: pts,
      padding: EdgeInsets.fromLTRB(40, MediaQuery.paddingOf(context).top + 70, 40, 60),
      maxZoom: 17,
    ));
  }

  Future<void> _goToMe() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Zet locatie aan op je telefoon om jezelf op de kaart te zien.');
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception('RunWise mag je locatie niet gebruiken. Dit kun je aanzetten in de instellingen van je telefoon.');
      }
      if (!_showMe) setState(() => _showMe = true);
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));
      final zoom = _controller.camera.zoom < 15 ? 16.0 : _controller.camera.zoom;
      _controller.move(ll.LatLng(pos.latitude, pos.longitude), zoom);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final top = MediaQuery.paddingOf(context).top;
    final hasProfile = d.profile.length >= 3;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: RwColors.background,
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RouteMap(
                      polyline: d.polyline,
                      windSpeedKmh: d.windSpeedKmh,
                      windFromDegrees: d.windFromDegrees,
                      reversed: d.reversed,
                      controller: _controller,
                      showMyLocation: _showMe,
                      highlightFraction: _highlight,
                      borderRadius: 0,
                      overlayPadding: EdgeInsets.only(top: top + 52),
                    ),
                  ),
                  // Titelbalk over de kaart.
                  Positioned(
                    top: top + 6,
                    left: 8,
                    right: 8,
                    child: Row(
                      children: [
                        _CircleButton(
                          icon: Icons.close,
                          tooltip: 'Sluiten',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: RwColors.background.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: RwColors.border),
                            ),
                            child: Text(
                              '${d.title} · ${Fmt.km(d.distanceMeters, decimals: 1)}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 36,
                    child: Column(
                      children: [
                        _CircleButton(icon: Icons.route_outlined, tooltip: 'Hele route tonen', onTap: _fitRoute),
                        const SizedBox(height: 10),
                        _CircleButton(
                          icon: Icons.my_location,
                          tooltip: 'Naar mijn locatie',
                          onTap: _locating ? null : _goToMe,
                          busy: _locating,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (hasProfile)
              Container(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.paddingOf(context).bottom),
                decoration: const BoxDecoration(
                  color: RwColors.surface,
                  border: Border(top: BorderSide(color: RwColors.border)),
                ),
                child: ElevationProfileChart(profile: d.profile, highlight: _highlight, height: 110),
              ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.tooltip, required this.onTap, this.busy = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: RwColors.background.withValues(alpha: 0.9),
          shape: const CircleBorder(side: BorderSide(color: RwColors.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Center(
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(icon, size: 22, color: RwColors.text),
              ),
            ),
          ),
        ),
      );
}

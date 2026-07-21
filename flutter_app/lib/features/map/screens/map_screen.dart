import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:trucker_gps/core/constants/app_constants.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/providers/navigation_provider.dart';
import 'package:trucker_gps/providers/location_provider.dart';
import 'package:trucker_gps/features/map/widgets/navigation_banner.dart';
import 'package:trucker_gps/features/map/widgets/speed_hud.dart';
import 'package:trucker_gps/features/map/widgets/search_bar_widget.dart';
import 'package:trucker_gps/features/map/widgets/poi_marker_layer.dart';
import 'package:trucker_gps/features/map/widgets/settings_panel.dart';
import 'package:trucker_gps/providers/settings_provider.dart';
import 'package:trucker_gps/models/settings_models.dart';
import 'package:trucker_gps/features/truck_profile/screens/truck_profile_screen.dart';
import 'package:trucker_gps/features/weather/screens/weather_screen.dart';
import 'package:trucker_gps/features/fuel/screens/fuel_screen.dart';

// Only import permission_handler on non-web platforms
import 'package:trucker_gps/core/platform/permissions.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  FlutterTts? _tts;
  LatLng _center = const LatLng(39.8283, -98.5795);
  bool _followUser = true;
  bool _mapReady = false;
  String _mapLayer = 'dark';
  String? _lastSpokenInstruction;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      _tts = FlutterTts();
      await _tts!.setLanguage('en-US');
      await _tts!.setSpeechRate(0.45);
      await _tts!.setVolume(1.0);
    } catch (_) {
      // TTS may not work on all platforms/browsers
      _tts = null;
    }
  }

  Future<void> _initLocation() async {
    // On web, geolocator uses the browser's geolocation API directly
    // No need for permission_handler
    if (!kIsWeb) {
      final granted = await AppPermissions.requestLocation();
      if (!granted) {
        if (mounted) setState(() => _mapReady = true);
        return;
      }
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() {
          _center = LatLng(pos.latitude, pos.longitude);
          _mapReady = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _mapReady = true);
    }
  }

  String _getTileUrl() {
    switch (_mapLayer) {
      case 'satellite':
        return AppConstants.osmSatelliteUrl;
      case 'standard':
        return AppConstants.osmStandardTileUrl;
      case 'dark':
      default:
        return AppConstants.osmDarkTileUrl;
    }
  }

  void _speakInstruction(String instruction) async {
    if (_tts == null) return;
    if (instruction != _lastSpokenInstruction) {
      _lastSpokenInstruction = instruction;
      try {
        await _tts!.stop();
        await _tts!.speak(instruction);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navigationProvider);
    final locationAsync = ref.watch(locationStreamProvider);
    final speed = ref.watch(currentSpeedMphProvider);
    final settings = ref.watch(settingsProvider);

    // Follow user location on map
    ref.listen(locationStreamProvider, (previous, next) {
      next.whenData((pos) {
        final latLng = LatLng(pos.latitude, pos.longitude);
        if (_followUser && _mapReady) {
          try {
            final currentNavState = ref.read(navigationProvider);
            _mapController.move(
                latLng,
                currentNavState.status == NavigationStatus.navigating
                    ? AppConstants.navigationZoom
                    : AppConstants.defaultZoom);
          } catch (_) {}
        }

        // Update navigation progress and speak instructions
        final currentNavState = ref.read(navigationProvider);
        if (currentNavState.status == NavigationStatus.navigating) {
          ref.read(navigationProvider.notifier).updateProgress(latLng);
          final step = currentNavState.currentStep;
          if (step != null) _speakInstruction(step.instruction);
        }
      });
    });

    // Zoom to fit route when calculation completes
    ref.listen(navigationProvider, (previous, next) {
      if (previous?.status != NavigationStatus.routing &&
          next.status == NavigationStatus.routing &&
          next.activeRoute != null &&
          next.activeRoute!.polyline.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(next.activeRoute!.polyline);
        try {
          _mapController.fitCamera(CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.only(
                top: 100, bottom: 250, left: 40, right: 40),
          ));
        } catch (_) {}
        setState(() => _followUser = false);
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.bg1,
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: AppConstants.defaultZoom,
              minZoom: AppConstants.minZoom,
              maxZoom: AppConstants.maxZoom,
              onMapEvent: (event) {
                if (event.source != MapEventSource.mapController) {
                  if (_followUser) setState(() => _followUser = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _getTileUrl(),
                userAgentPackageName: 'com.truckergps.app',
                retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
                panBuffer: 2,
                keepBuffer: 5,
              ),

              // Route polyline
              if (navState.activeRoute != null)
                PolylineLayer(
                  polylines: [
                    // Outer glow / casing
                    Polyline(
                      points: navState.activeRoute!.polyline,
                      color: AppTheme.primaryDark.withValues(alpha: 0.6),
                      strokeWidth: 11.0,
                    ),
                    // Main route line
                    Polyline(
                      points: navState.activeRoute!.polyline,
                      color: AppTheme.primary,
                      strokeWidth: 7.0,
                    ),
                  ],
                ),

              // POI markers
              PoiMarkerLayer(pois: navState.nearbyPois),

              // Location + destination markers
              locationAsync.when(
                data: (pos) => MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(pos.latitude, pos.longitude),
                      width: 52,
                      height: 52,
                      child: _buildTruckMarker(settings.vehicleType),
                    ),
                    if (navState.activeRoute != null)
                      Marker(
                        point: navState.activeRoute!.destination,
                        width: 42,
                        height: 42,
                        child: _buildDestMarker(),
                      ),
                  ],
                ),
                loading: () => const MarkerLayer(markers: []),
                error: (_, __) => const MarkerLayer(markers: []),
              ),
            ],
          ),

          // ── TOP overlay (search bar / nav banner) ────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: navState.activeRoute != null
                  ? NavigationBanner(navState: navState)
                  : SearchBarWidget(
                      onDestinationSelected: (dest, name) {
                        locationAsync.whenData((pos) {
                          ref.read(navigationProvider.notifier).calculateRoute(
                                origin: LatLng(pos.latitude, pos.longitude),
                                destination: dest,
                                destinationName: name,
                                avoidTolls: settings.avoidTolls,
                                avoidHighways: settings.avoidHighways,
                              );
                        });
                      },
                      onFilterSelected: (category) {
                        locationAsync.whenData((pos) {
                          ref.read(navigationProvider.notifier).searchNearbyPois(
                                LatLng(pos.latitude, pos.longitude),
                                category,
                              );
                        });
                      },
                    ),
            ),
          ),

          // ── BOTTOM overlay (speed HUD + buttons + route bar) ─────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (navState.status == NavigationStatus.routing)
                      _buildRouteSummaryBar(navState),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SpeedHud(speedMph: speed),
                        const Spacer(),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _floatButton(
                              icon: _mapLayer == 'dark'
                                  ? Icons.satellite_alt
                                  : _mapLayer == 'standard'
                                      ? Icons.dark_mode
                                      : Icons.map,
                              tooltip: 'Map Layer',
                              onTap: () => setState(() {
                                if (_mapLayer == 'dark') {
                                  _mapLayer = 'standard';
                                } else if (_mapLayer == 'standard')
                                  _mapLayer = 'satellite';
                                else
                                  _mapLayer = 'dark';
                              }),
                            ),
                            const SizedBox(height: 8),
                            _floatButton(
                              icon: _followUser
                                  ? Icons.my_location
                                  : Icons.location_searching,
                              tooltip: 'Recenter',
                              color: _followUser ? AppTheme.primary : null,
                              onTap: () {
                                setState(() => _followUser = true);
                                _mapController.move(
                                    _center, AppConstants.defaultZoom);
                              },
                            ),
                            const SizedBox(height: 8),
                            _floatButton(
                              icon: Icons.tune_rounded,
                              tooltip: 'Settings',
                              onTap: () => showSettingsPanel(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Loading overlay
          if (navState.isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    SizedBox(height: 16),
                    Text('Calculating truck route...',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),

          // Error snackbar-style
          if (navState.error != null)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(navState.error!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ),
                    GestureDetector(
                      onTap: () => ref
                          .read(navigationProvider.notifier)
                          .cancelNavigation(),
                      child: const Icon(Icons.close,
                          color: Colors.white70, size: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTruckMarker(VehicleType type) => Container(
        decoration: BoxDecoration(
          color: AppTheme.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: AppTheme.primary.withOpacity(0.5),
                blurRadius: 16,
                spreadRadius: 4)
          ],
        ),
        child: Icon(
          type == VehicleType.truck
              ? Icons.local_shipping
              : Icons.directions_car_rounded,
          color: Colors.black,
          size: 26,
        ),
      );

  Widget _buildDestMarker() => Container(
        decoration: const BoxDecoration(
          color: AppTheme.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Color(0x80FF6B35), blurRadius: 12, spreadRadius: 3)
          ],
        ),
        child: const Icon(Icons.flag, color: Colors.white, size: 22),
      );

  Widget _floatButton(
      {required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
      Color? color}) {
    final isActive = color != null;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.primary.withOpacity(0.15)
                : AppTheme.panelBg,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive
                  ? AppTheme.primary.withOpacity(0.7)
                  : const Color(0xFF2A2A3F),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isActive
                    ? AppTheme.primary.withOpacity(0.25)
                    : Colors.black45,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon,
              color: isActive ? AppTheme.primary : AppTheme.textSecondary,
              size: 20),
        ),
      ),
    );
  }

  Widget _buildRouteSummaryBar(NavigationState navState) {
    final route = navState.activeRoute!;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF252535)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip(Icons.straighten,
                          '${route.distanceMiles.toStringAsFixed(1)} mi'),
                      const SizedBox(width: 8),
                      _chip(Icons.access_time, route.durationFormatted),
                      const SizedBox(width: 8),
                      _chip(Icons.place, '${navState.nearbyPois.length} stops'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  ref.read(navigationProvider.notifier).startNavigation();
                  setState(() => _followUser = true);
                },
                icon: const Icon(Icons.navigation, size: 16),
                label: const Text('Go'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size(0, 36),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () =>
                    ref.read(navigationProvider.notifier).cancelNavigation(),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: AppTheme.bg4,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.close,
                      color: AppTheme.textSecondary, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      );

  @override
  void dispose() {
    _tts?.stop();
    super.dispose();
  }
}


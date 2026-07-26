import 'dart:async';
import 'dart:math' show pi;
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
import 'package:trucker_gps/features/map/widgets/speed_limit_sign.dart';
import 'package:trucker_gps/features/map/widgets/search_bar_widget.dart';
import 'package:trucker_gps/features/map/widgets/poi_marker_layer.dart';
import 'package:trucker_gps/features/map/widgets/settings_panel.dart';
import 'package:trucker_gps/providers/settings_provider.dart';
import 'package:trucker_gps/models/settings_models.dart';
import 'package:trucker_gps/services/speed_limit_service.dart';
import 'package:trucker_gps/services/sunrise_sunset_service.dart';
import 'package:trucker_gps/features/map/widgets/road_info_bar.dart';
// Only import permission_handler on non-web platforms
import 'package:trucker_gps/core/platform/permissions.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  FlutterTts? _tts;
  LatLng _center = const LatLng(39.8283, -98.5795);
  bool _followUser = true;
  bool _mapReady = false;
  bool _isNightMode = false;
  String? _lastSpokenInstruction;
  int? _speedLimit;
  double _currentHeading = 0.0; // live GPS bearing in degrees (0 = North)
  Timer? _nightModeTimer;
  
  AnimationController? _movementController;
  final ValueNotifier<LatLng?> _animatedTruckPosition = ValueNotifier(null);
  
  final _speedLimitService = SpeedLimitService();
  final _sunService = SunriseSunsetService();

  @override
  void initState() {
    super.initState();
    _initLocation();
    _initTts();
    _startNightModeWatcher();
  }

  @override
  void dispose() {
    _movementController?.dispose();
    _animatedTruckPosition.dispose();
    _nightModeTimer?.cancel();
    _tts?.stop();
    super.dispose();
  }

  void _startNightModeWatcher() {
    // Check immediately, then every 5 minutes
    _checkNightMode();
    _nightModeTimer = Timer.periodic(const Duration(minutes: 5), (_) => _checkNightMode());
  }

  void _checkNightMode() {
    final pos = ref.read(locationStreamProvider).valueOrNull;
    if (pos == null) return;
    final isNight = _sunService.isNightTime(pos.latitude, pos.longitude);
    if (isNight != _isNightMode) {
      if (mounted) setState(() => _isNightMode = isNight);
    }
  }

  Future<void> _updateSpeedLimit(LatLng location) async {
    final limit = await _speedLimitService.getSpeedLimit(location);
    if (mounted && limit != _speedLimit) {
      setState(() => _speedLimit = limit);
    }
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

  bool _isDarkMode(AppSettings settings, BuildContext context) {
    switch (settings.mapThemeMode) {
      case MapThemeMode.light:
        return false;
      case MapThemeMode.dark:
        return true;
      case MapThemeMode.system:
        return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
      case MapThemeMode.auto:
        return _isNightMode;
    }
  }

  String _getTileUrl(AppSettings settings, BuildContext context) {
    // We use the standard tile URL, and apply a color filter if dark mode is active
    return AppConstants.osmStandardTileUrl;
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
    // Only watch specific parts of state so distance updates don't rebuild the entire map
    final activeRoute = ref.watch(navigationProvider.select((s) => s.activeRoute));
    final nearbyPois = ref.watch(navigationProvider.select((s) => s.nearbyPois));
    final status = ref.watch(navigationProvider.select((s) => s.status));
    final selectedPoi = ref.watch(navigationProvider.select((s) => s.selectedPoi));
    final isLoading = ref.watch(navigationProvider.select((s) => s.isLoading));
    final error = ref.watch(navigationProvider.select((s) => s.error));
    // NOTE: locationAsync and speed are NOT watched here to avoid full-tree
    // rebuilds on every GPS tick. They are isolated inside Consumer widgets below.
    final settings = ref.watch(settingsProvider);
    
    // Attach voice alert callback
    ref.read(navigationProvider.notifier).onVoiceAlert = _speakInstruction;

    // Follow user location on map
    ref.listen(locationStreamProvider, (previous, next) {
      next.whenData((pos) {
        final latLng = LatLng(pos.latitude, pos.longitude);
        // Store heading for marker rotation
        if (pos.heading >= 0 && mounted) {
          setState(() => _currentHeading = pos.heading);
        }
        if (_followUser && _mapReady) {
          try {
            final currentNavState = ref.read(navigationProvider);
            final isNavigating = currentNavState.status == NavigationStatus.navigating;
            
            // Forward-looking camera offset
            LatLng targetCenter = latLng;
            if (isNavigating && pos.heading >= 0) {
              targetCenter = const Distance().offset(latLng, 150, pos.heading);
            }

            final targetRotation = pos.heading >= 0 ? (360.0 - pos.heading) : 0.0;
            final targetZoom = isNavigating ? AppConstants.navigationZoom : AppConstants.defaultZoom;

            // Direct move provides a smooth 1Hz snap synced perfectly with GPS
            _mapController.move(targetCenter, targetZoom);
            _mapController.rotate(targetRotation);
          } catch (_) {}
        }

        // Fetch speed limit for new position (throttled inside service)
        _updateSpeedLimit(latLng);

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
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(
                  const LatLng(-90, -180),
                  const LatLng(90, 180),
                ),
              ),
              onMapEvent: (event) {
                if (event.source != MapEventSource.mapController) {
                  if (_followUser) setState(() => _followUser = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _getTileUrl(settings, context),
                userAgentPackageName: 'com.truckergps.app',
                panBuffer: 1,
                keepBuffer: 3,
                tileBuilder: _isDarkMode(settings, context)
                    ? (context, tileWidget, tile) {
                        return ColorFiltered(
                          colorFilter: const ColorFilter.matrix([
                            -1,  0,  0, 0, 255,
                             0, -1,  0, 0, 255,
                             0,  0, -1, 0, 255,
                             0,  0,  0, 1,   0,
                          ]),
                          child: tileWidget,
                        );
                      }
                    : null,
              ),

              // Route polyline
              if (activeRoute != null)
                PolylineLayer(
                  simplificationTolerance: 1.0,
                  polylines: [
                    // Outer glow / casing
                    Polyline(
                      points: activeRoute.remainingPolyline.isNotEmpty 
                          ? activeRoute.remainingPolyline 
                          : activeRoute.polyline,
                      color: AppTheme.primaryDark.withValues(alpha: 0.6),
                      strokeWidth: 11.0,
                      strokeJoin: StrokeJoin.bevel,
                      strokeCap: StrokeCap.butt,
                    ),
                    // Main route line
                    Polyline(
                      points: activeRoute.remainingPolyline.isNotEmpty 
                          ? activeRoute.remainingPolyline 
                          : activeRoute.polyline,
                      color: AppTheme.primary,
                      strokeWidth: 7.0,
                      strokeJoin: StrokeJoin.bevel,
                      strokeCap: StrokeCap.butt,
                    ),
                  ],
                ),

              // POI markers
              PoiMarkerLayer(pois: nearbyPois),

              // Location + destination markers — isolated Consumer so only
              // this small widget rebuilds on every GPS tick, not the whole map.
              Consumer(
                builder: (context, ref, _) {
                  final locationAsync = ref.watch(locationStreamProvider);
                  final vehicleType = ref.watch(settingsProvider.select((s) => s.vehicleType));
                  return locationAsync.when(
                    data: (pos) => MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(pos.latitude, pos.longitude),
                          width: 52,
                          height: 52,
                          child: _buildTruckMarker(vehicleType),
                        ),
                        if (activeRoute != null)
                          Marker(
                            point: activeRoute.destination,
                            width: 42,
                            height: 42,
                            child: _buildDestMarker(),
                          ),
                      ],
                    ),
                    loading: () => const MarkerLayer(markers: []),
                    error: (_, __) => const MarkerLayer(markers: []),
                  );
                },
              ),
            ],
          ),

          // ── TOP overlay (search bar / nav banner) ────────────────────────
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 0,
            right: 0,
            child: activeRoute != null
                ? Consumer(
                    builder: (context, ref, _) {
                      return NavigationBanner(
                        navState: ref.watch(navigationProvider),
                        onCancel: () => ref.read(navigationProvider.notifier).cancelNavigation(),
                      );
                    },
                  )
                : SearchBarWidget(
                    onDestinationSelected: (dest, name) {
                      ref.read(locationStreamProvider).whenData((pos) {
                        ref.read(navigationProvider.notifier).calculateRoute(
                              origin: LatLng(pos.latitude, pos.longitude),
                              destination: dest,
                              destinationName: name,
                              avoidTolls: settings.avoidTolls,
                              avoidHighways: settings.avoidHighways,
                            );
                      });
                    },
                    onFiltersChanged: (categories) {
                      ref.read(locationStreamProvider).whenData((pos) {
                        ref.read(navigationProvider.notifier).searchNearbyPois(
                              LatLng(pos.latitude, pos.longitude),
                              categories,
                            );
                      });
                    },
                  ),
          ),

          // ── BOTTOM overlay (speed HUD + buttons + route bar) ─────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status == NavigationStatus.routing)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Consumer(
                        builder: (context, ref, _) {
                          final fullNavState = ref.watch(navigationProvider);
                          return _buildRouteSummaryBar(fullNavState);
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Isolated Consumer — only SpeedHud rebuilds on GPS ticks
                        if (settings.showSpeedHud)
                          Consumer(
                            builder: (context, ref, _) {
                              final speed = ref.watch(currentSpeedMphProvider);
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SpeedHud(speedMph: speed),
                                  const SizedBox(width: 8),
                                  SpeedLimitSign(
                                    speedLimit: _speedLimit,
                                    currentSpeedMph: speed,
                                  ),
                                ],
                              );
                            },
                          ),
                        const Spacer(),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _floatButton(
                              icon: _followUser
                                  ? Icons.my_location
                                  : Icons.location_searching,
                              tooltip: 'Recenter',
                              color: _followUser ? AppTheme.primary : null,
                              onTap: () {
                                setState(() => _followUser = true);
                                final pos = ref.read(locationStreamProvider).valueOrNull;
                                if (pos != null) {
                                  _mapController.move(LatLng(pos.latitude, pos.longitude), AppConstants.defaultZoom);
                                }
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
                  ),
                  if (status == NavigationStatus.navigating)
                    Consumer(
                      builder: (context, ref, _) {
                        final navState = ref.watch(navigationProvider);
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Road info bar (highway sign)
                            RoadInfoBar(
                              roadRef: navState.currentRoadRef,
                              roadName: navState.currentRoadName,
                            ),
                            _buildBottomNavBanner(navState),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

          // Loading overlay
          if (isLoading)
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
          if (error != null)
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
                      child: Text(error,
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

  Widget _buildTruckMarker(VehicleType type) {
    // The map canvas is rotated so heading faces up on screen.
    // Markers rotate with the map, so the raw heading angle puts the
    // arrow pointing in the correct direction of travel.
    final angle = _currentHeading * pi / 180.0;
    return Transform.rotate(
      angle: angle,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF14CBA8),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF14CBA8).withOpacity(0.5),
              blurRadius: 16,
              spreadRadius: 4,
            )
          ],
        ),
        child: const Icon(
          Icons.navigation,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

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
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: isActive ? AppTheme.primary : const Color(0xFF003833),
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavBanner(NavigationState navState) {
    if (navState.activeRoute == null) return const SizedBox.shrink();

    // Use live remaining duration; fall back to total if not yet computed
    final remainingSecs = navState.remainingDurationSeconds
        ?? navState.activeRoute!.durationSeconds;
    final remainingMeters = navState.remainingDistanceMeters
        ?? navState.activeRoute!.distanceMeters;
    final remainingMiles = remainingMeters / 1609.34;

    final now = DateTime.now();
    final arrivalTime = now.add(Duration(seconds: remainingSecs.round()));
    final timeStr =
        '${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      color: const Color(0xFF003833),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ETA
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 4),
                  const Text('ETA',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const Text('Arrival',
                  style: TextStyle(color: Colors.white60, fontSize: 13)),
            ],
          ),

          // Remaining distance (live)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    remainingMiles < 10
                        ? remainingMiles.toStringAsFixed(1)
                        : remainingMiles.toStringAsFixed(0),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 2),
                  const Text('mi',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const Text('To go',
                  style: TextStyle(color: Colors.white60, fontSize: 13)),
            ],
          ),

          // Exit button
          ElevatedButton(
            onPressed: () =>
                ref.read(navigationProvider.notifier).cancelNavigation(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0099DD),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Exit',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ],
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
}

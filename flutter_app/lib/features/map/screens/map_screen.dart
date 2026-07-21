import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:trucker_gps/core/constants/app_constants.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/providers/navigation_provider.dart';
import 'package:trucker_gps/providers/location_provider.dart';
import 'package:trucker_gps/models/route_models.dart';
import 'package:trucker_gps/features/map/widgets/navigation_banner.dart';
import 'package:trucker_gps/features/map/widgets/speed_hud.dart';
import 'package:trucker_gps/features/map/widgets/search_bar_widget.dart';
import 'package:trucker_gps/features/map/widgets/poi_marker_layer.dart';
import 'package:trucker_gps/features/hos/screens/hos_logbook_screen.dart';
import 'package:trucker_gps/features/truck_profile/screens/truck_profile_screen.dart';
import 'package:trucker_gps/features/weather/screens/weather_screen.dart';
import 'package:trucker_gps/features/fuel/screens/fuel_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final FlutterTts _tts = FlutterTts();
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
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
  }

  Future<void> _initLocation() async {
    final status = await Permission.location.request();
    if (!status.isGranted) return;
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
        return AppConstants.osmTileUrl;
      default:
        return AppConstants.osmDarkTileUrl;
    }
  }

  void _speakInstruction(String instruction) async {
    if (instruction != _lastSpokenInstruction) {
      _lastSpokenInstruction = instruction;
      await _tts.stop();
      await _tts.speak(instruction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navigationProvider);
    final locationAsync = ref.watch(locationStreamProvider);
    final speed = ref.watch(currentSpeedMphProvider);

    // Follow user location on map
    locationAsync.whenData((pos) {
      final latLng = LatLng(pos.latitude, pos.longitude);
      if (_followUser && _mapReady) {
        try {
          _mapController.move(
              latLng,
              navState.status == NavigationStatus.navigating
                  ? AppConstants.navigationZoom
                  : AppConstants.defaultZoom);
        } catch (_) {}
      }

      // Update navigation progress
      if (navState.status == NavigationStatus.navigating) {
        ref.read(navigationProvider.notifier).updateProgress(latLng);

        // Speak current instruction
        final step = navState.currentStep;
        if (step != null) {
          _speakInstruction(step.instruction);
        }
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.bg1,
      body: Stack(
        children: [
          // ── Map ───────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: AppConstants.defaultZoom,
              minZoom: AppConstants.minZoom,
              maxZoom: AppConstants.maxZoom,
              onMapEvent: (event) {
                // Disable follow mode if user drags map
                if (event is MapEventScrollWheelZoom ||
                    event is MapEventMove && event.source != MapEventSource.mapController) {
                  if (_followUser) setState(() => _followUser = false);
                }
              },
            ),
            children: [
              // Tile layer
              TileLayer(
                urlTemplate: _getTileUrl(),
                userAgentPackageName: 'com.truckergps.app',
                retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
              ),

              // Route polyline
              if (navState.activeRoute != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: navState.activeRoute!.polyline,
                      color: AppTheme.primary.withOpacity(0.85),
                      strokeWidth: 7.0,
                      borderColor: AppTheme.primaryDark,
                      borderStrokeWidth: 1.0,
                    ),
                  ],
                ),

              // POI markers along route
              PoiMarkerLayer(pois: navState.nearbyPois),

              // Current location marker
              locationAsync.when(
                data: (pos) => MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(pos.latitude, pos.longitude),
                      width: 56,
                      height: 56,
                      child: _buildTruckMarker(),
                    ),
                    // Destination marker
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

          // ── UI Overlays ────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Turn-by-turn banner (when navigating/routing)
                if (navState.activeRoute != null)
                  NavigationBanner(navState: navState)
                else
                  // Search bar when idle
                  SearchBarWidget(
                    onDestinationSelected: (dest, name) {
                      locationAsync.whenData((pos) {
                        ref.read(navigationProvider.notifier).calculateRoute(
                              origin: LatLng(pos.latitude, pos.longitude),
                              destination: dest,
                              destinationName: name,
                            );
                      });
                    },
                  ),

                const Spacer(),

                // ── Bottom HUD ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Speed + controls row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Speed HUD
                          SpeedHud(speedMph: speed),
                          const Spacer(),
                          // Right-side control column
                          Column(
                            children: [
                              _mapLayerButton(),
                              const SizedBox(height: 10),
                              _recenterButton(),
                              const SizedBox(height: 10),
                              _menuButton(),
                            ],
                          ),
                        ],
                      ),

                      // Route summary bar (when route is calculated but not navigating)
                      if (navState.status == NavigationStatus.routing)
                        _buildRouteSummaryBar(navState),
                    ],
                  ),
                ),
              ],
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
        ],
      ),
    );
  }

  Widget _buildTruckMarker() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.5),
            blurRadius: 16,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(Icons.local_shipping, color: Colors.black, size: 28),
    );
  }

  Widget _buildDestMarker() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x80FF6B35),
            blurRadius: 12,
            spreadRadius: 3,
          ),
        ],
      ),
      child: const Icon(Icons.flag, color: Colors.white, size: 24),
    );
  }

  Widget _mapLayerButton() {
    return _floatButton(
      icon: _mapLayer == 'satellite'
          ? Icons.map
          : _mapLayer == 'dark'
              ? Icons.satellite_alt
              : Icons.dark_mode,
      tooltip: 'Map Layer',
      onTap: () {
        setState(() {
          if (_mapLayer == 'dark') _mapLayer = 'standard';
          else if (_mapLayer == 'standard') _mapLayer = 'satellite';
          else _mapLayer = 'dark';
        });
      },
    );
  }

  Widget _recenterButton() {
    return _floatButton(
      icon: _followUser ? Icons.my_location : Icons.location_searching,
      tooltip: 'Recenter',
      color: _followUser ? AppTheme.primary : null,
      onTap: () {
        setState(() => _followUser = true);
        final pos = ref.read(currentLatLngProvider);
        if (pos != null) {
          _mapController.move(pos, AppConstants.defaultZoom);
        }
      },
    );
  }

  Widget _menuButton() {
    return _floatButton(
      icon: Icons.menu,
      tooltip: 'Menu',
      onTap: () => _showSideMenu(),
    );
  }

  Widget _floatButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: AppTheme.bg2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF252535)),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))
          ],
        ),
        child: Icon(icon, color: color ?? AppTheme.textSecondary, size: 22),
      ),
    );
  }

  Widget _buildRouteSummaryBar(NavigationState navState) {
    if (navState.activeRoute == null) return const SizedBox.shrink();
    final route = navState.activeRoute!;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF252535)),
      ),
      child: Row(
        children: [
          _summaryChip(Icons.straighten, '${route.distanceMiles.toStringAsFixed(1)} mi'),
          const SizedBox(width: 16),
          _summaryChip(Icons.access_time, route.durationFormatted),
          const SizedBox(width: 16),
          _summaryChip(Icons.place, '${navState.nearbyPois.length} stops'),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () {
              ref.read(navigationProvider.notifier).startNavigation();
              setState(() => _followUser = true);
            },
            icon: const Icon(Icons.navigation, size: 18),
            label: const Text('Go'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => ref.read(navigationProvider.notifier).cancelNavigation(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.bg4,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.primary),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }

  void _showSideMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SideMenuSheet(),
    );
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}

// ── Side menu sheet ────────────────────────────────────────────────────────────

class _SideMenuSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'TruckerGPS',
              style: TextStyle(
                color: AppTheme.primary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            _menuItem(context, Icons.person_outline, 'Truck Profile',
                'Height, weight & restrictions', () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const TruckProfileScreen()));
            }),
            _menuItem(context, Icons.description_outlined, 'HOS Logbook',
                'Hours of service & ELD', () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const HosLogbookScreen(userId: 'driver_001')));
            }),
            _menuItem(context, Icons.local_gas_station_outlined, 'Fuel Prices',
                'Diesel prices near you', () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FuelScreen()));
            }),
            _menuItem(context, Icons.cloud_outlined, 'Weather',
                'Road weather & alerts', () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const WeatherScreen()));
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(BuildContext ctx, IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.bg3,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppTheme.primary, size: 22),
      ),
      title: Text(title,
          style: const TextStyle(
              color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

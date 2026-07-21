import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:trucker_gps/core/constants/app_constants.dart';
import 'package:trucker_gps/features/routing/screens/route_planner_screen.dart';
import 'package:trucker_gps/features/poi/screens/poi_search_screen.dart';
import 'package:trucker_gps/features/hos/screens/hos_logbook_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _currentLocation = const LatLng(39.8283, -98.5795); // Default US center
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _isLoading = false;
        });
      } catch (e) {
        // Fallback to default
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: AppConstants.defaultZoom,
              minZoom: AppConstants.minZoom,
              maxZoom: AppConstants.maxZoom,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.truckergps.app',
              ),
              if (!_isLoading)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.local_shipping,
                        color: Colors.blue,
                        size: 30,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          
          // Navigation UI Overlay
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Search Bar
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Where to?',
                          border: InputBorder.none,
                          icon: Icon(Icons.search),
                        ),
                        onSubmitted: (value) {
                          // TODO: Implement search routing
                        },
                      ),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Floating Action Buttons
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton(
                          heroTag: 'recenter',
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          onPressed: () {
                            _mapController.move(_currentLocation, AppConstants.defaultZoom);
                          },
                          child: const Icon(Icons.my_location),
                        ),
                        const SizedBox(height: 16),
                        FloatingActionButton(
                          heroTag: 'menu',
                          onPressed: () {
                            _showBottomMenu(context);
                          },
                          child: const Icon(Icons.menu),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBottomMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.directions),
                  title: const Text('Route Planner'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutePlannerScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.local_parking),
                  title: const Text('Find Truck Stops & POI'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => PoiSearchScreen(
                      currentLat: _currentLocation.latitude,
                      currentLon: _currentLocation.longitude,
                    )));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('HOS/ELD Logbook'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HosLogbookScreen(userId: 'driver_123')));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Truck Profile'),
                  onTap: () {
                    // TODO: Navigate to Truck Profile Setup
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

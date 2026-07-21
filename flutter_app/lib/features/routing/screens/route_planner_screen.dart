import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trucker_gps/services/api_service.dart';
import 'package:trucker_gps/providers/api_providers.dart';

class RoutePlannerScreen extends ConsumerStatefulWidget {
  const RoutePlannerScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends ConsumerState<RoutePlannerScreen> {
  final _originController = TextEditingController();
  final _destController = TextEditingController();
  
  bool _isLoading = false;
  Map<String, dynamic>? _routeResult;
  String? _error;

  @override
  void dispose() {
    _originController.dispose();
    _destController.dispose();
    super.dispose();
  }

  Future<void> _calculateRoute() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _routeResult = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      
      // In a real app, we'd use the geocoder here first.
      // For testing, let's hardcode a trip from Chicago to Indy
      final result = await apiService.getRoute(
        startLat: 41.8781,
        startLon: -87.6298,
        endLat: 39.7684,
        endLon: -86.1581,
        truckProfile: {
          'height_meters': 4.11,
          'weight_kg': 36287.0,
          'hazmat': false,
        },
      );

      setState(() {
        _routeResult = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Planner'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _originController,
              decoration: const InputDecoration(
                labelText: 'Origin',
                prefixIcon: Icon(Icons.my_location),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _destController,
              decoration: const InputDecoration(
                labelText: 'Destination',
                prefixIcon: Icon(Icons.location_on),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _calculateRoute,
              child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Calculate Route'),
            ),
            
            const SizedBox(height: 24),
            
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.error.withOpacity(0.1),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
              
            if (_routeResult != null)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Route Summary', style: Theme.of(context).textTheme.titleLarge),
                        const Divider(),
                        Text('Distance: ${_routeResult!['distance_miles']} miles'),
                        Text('Duration: ${_routeResult!['duration_formatted']}'),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _routeResult!['steps']?.length ?? 0,
                            itemBuilder: (context, index) {
                              final step = _routeResult!['steps'][index];
                              return ListTile(
                                leading: const Icon(Icons.directions),
                                title: Text(step['instruction']),
                                subtitle: Text('${step['distance_miles']} mi'),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

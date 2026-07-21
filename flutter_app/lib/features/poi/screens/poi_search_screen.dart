import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trucker_gps/services/api_service.dart';
import 'package:trucker_gps/providers/api_providers.dart';

class PoiSearchScreen extends ConsumerStatefulWidget {
  final double currentLat;
  final double currentLon;

  const PoiSearchScreen({
    Key? key,
    required this.currentLat,
    required this.currentLon,
  }) : super(key: key);

  @override
  ConsumerState<PoiSearchScreen> createState() => _PoiSearchScreenState();
}

class _PoiSearchScreenState extends ConsumerState<PoiSearchScreen> {
  String _selectedCategory = 'truck_stop';
  bool _isLoading = false;
  List<dynamic> _results = [];
  String? _error;

  final Map<String, String> _categories = {
    'truck_stop': 'Truck Stops',
    'weigh_station': 'Weigh Stations',
    'rest_area': 'Rest Areas',
    'truck_parking': 'Parking',
  };

  @override
  void initState() {
    super.initState();
    _fetchPois();
  }

  Future<void> _fetchPois() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      
      // Calculate a rough bounding box (approx 25 miles)
      const double degOffset = 0.35;
      
      final pois = await apiService.getPoisInBbox(
        widget.currentLat - degOffset,
        widget.currentLon - degOffset,
        widget.currentLat + degOffset,
        widget.currentLon + degOffset,
        types: _selectedCategory,
      );

      setState(() {
        _results = pois;
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
        title: const Text('Find Places'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.entries.map((entry) {
                  final isSelected = _selectedCategory == entry.key;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: FilterChip(
                      label: Text(entry.value),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedCategory = entry.key;
                          });
                          _fetchPois();
                        }
                      },
                      selectedColor: Theme.of(context).colorScheme.primary,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _results.isEmpty
                  ? const Center(child: Text('No places found nearby.'))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final poi = _results[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                              child: _getIconForType(poi['type']),
                            ),
                            title: Text(poi['name'] ?? 'Unknown Location'),
                            subtitle: Text(poi['brand'] ?? poi['type'].replaceAll('_', ' ').toUpperCase()),
                            trailing: IconButton(
                              icon: const Icon(Icons.directions),
                              onPressed: () {
                                // TODO: Route to this POI
                                Navigator.pop(context, poi);
                              },
                            ),
                            onTap: () {
                              _showPoiDetails(context, poi);
                            },
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _getIconForType(String type) {
    switch (type) {
      case 'truck_stop':
        return const Icon(Icons.local_gas_station);
      case 'weigh_station':
        return const Icon(Icons.monitor_weight);
      case 'rest_area':
        return const Icon(Icons.park);
      case 'truck_parking':
        return const Icon(Icons.local_parking);
      default:
        return const Icon(Icons.place);
    }
  }

  void _showPoiDetails(BuildContext context, Map<String, dynamic> poi) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(poi['name'] ?? 'Unknown', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('Amenities:', style: Theme.of(context).textTheme.titleMedium),
                Wrap(
                  spacing: 8,
                  children: (poi['amenities'] as List? ?? []).map((a) => Chip(label: Text(a.toString()))).toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.directions),
                    label: const Text('Navigate Here'),
                    onPressed: () {
                      Navigator.pop(context); // Close sheet
                      Navigator.pop(context, poi); // Close search screen and return POI
                    },
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}

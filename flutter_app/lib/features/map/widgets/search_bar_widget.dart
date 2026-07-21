import 'package:flutter/material.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/services/api_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';

/// Destination search bar with address autocomplete using Nominatim
class SearchBarWidget extends StatefulWidget {
  final void Function(LatLng destination, String name) onDestinationSelected;

  const SearchBarWidget({Key? key, required this.onDestinationSelected})
      : super(key: key);

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  final TextEditingController _controller = TextEditingController();
  final Dio _dio = Dio();
  List<Map<String, dynamic>> _suggestions = [];
  bool _isSearching = false;
  bool _showSuggestions = false;

  Future<void> _search(String query) async {
    if (query.length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    setState(() => _isSearching = true);

    try {
      final response = await _dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'json',
          'limit': 6,
          'countrycodes': 'us,ca,mx', // Limit to North America for trucking
        },
        options: Options(headers: {'User-Agent': 'TruckerGPS/1.0'}),
      );

      final results = (response.data as List)
          .map((r) => r as Map<String, dynamic>)
          .toList();

      if (mounted) {
        setState(() {
          _suggestions = results;
          _isSearching = false;
          _showSuggestions = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectSuggestion(Map<String, dynamic> suggestion) {
    final lat = double.tryParse(suggestion['lat'] ?? '0') ?? 0;
    final lon = double.tryParse(suggestion['lon'] ?? '0') ?? 0;
    final name = suggestion['display_name'] ?? '';

    _controller.text = name.split(',').take(2).join(', ');
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
    });

    widget.onDestinationSelected(LatLng(lat, lon), name);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search field
          Container(
            decoration: BoxDecoration(
              color: AppTheme.panelBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF252535)),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 3))
              ],
            ),
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Where to?',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 16),
                prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary,
                          ),
                        ),
                      )
                    : _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                color: AppTheme.textMuted),
                            onPressed: () {
                              _controller.clear();
                              setState(() {
                                _suggestions = [];
                                _showSuggestions = false;
                              });
                            },
                          )
                        : null,
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: _search,
            ),
          ),

          // Suggestions dropdown
          if (_showSuggestions && _suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: AppTheme.bg2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF252535)),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black54,
                      blurRadius: 16,
                      offset: Offset(0, 4))
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                padding: const EdgeInsets.symmetric(vertical: 8),
                separatorBuilder: (_, __) => const Divider(
                    color: Color(0xFF252535), height: 1, indent: 16),
                itemBuilder: (_, i) {
                  final s = _suggestions[i];
                  final parts = (s['display_name'] as String? ?? '').split(',');
                  final title = parts.take(2).join(',').trim();
                  final subtitle =
                      parts.skip(2).take(2).join(',').trim();

                  return ListTile(
                    onTap: () => _selectSuggestion(s),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.bg3,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.location_on,
                          color: AppTheme.primary, size: 18),
                    ),
                    title: Text(title,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    subtitle: subtitle.isNotEmpty
                        ? Text(subtitle,
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 12))
                        : null,
                    dense: true,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

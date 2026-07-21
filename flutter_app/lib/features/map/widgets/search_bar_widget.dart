import 'package:flutter/material.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';

/// Destination search bar — always full width, no jittery animations.
class SearchBarWidget extends StatefulWidget {
  final void Function(LatLng destination, String name) onDestinationSelected;

  const SearchBarWidget({super.key, required this.onDestinationSelected});

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final Dio _dio = Dio();

  List<Map<String, dynamic>> _suggestions = [];
  bool _isSearching = false;
  bool _hasFocus = false;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);

    _focusNode.addListener(() {
      setState(() => _hasFocus = _focusNode.hasFocus);
      if (_hasFocus) {
        _animCtrl.forward();
      } else {
        if (_controller.text.isEmpty) {
          setState(() => _suggestions = []);
        }
        _animCtrl.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _dio.close();
    _animCtrl.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _suggestions = [];
    });
  }

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
          'countrycodes': 'us,ca,mx',
        },
        options: Options(headers: {'User-Agent': 'TruckerGPS/1.0'}),
      );
      if (mounted) {
        setState(() {
          _suggestions = (response.data as List)
              .map((r) => r as Map<String, dynamic>)
              .toList();
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _select(Map<String, dynamic> s) {
    final lat = double.tryParse(s['lat'] ?? '0') ?? 0;
    final lon = double.tryParse(s['lon'] ?? '0') ?? 0;
    final name = s['display_name'] ?? '';
    _clear();
    widget.onDestinationSelected(LatLng(lat, lon), name);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Search field ─────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: AppTheme.panelBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _hasFocus
                    ? AppTheme.primary.withOpacity(0.6)
                    : const Color(0xFF252535),
                width: _hasFocus ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _hasFocus
                      ? AppTheme.primary.withOpacity(0.15)
                      : Colors.black38,
                  blurRadius: _hasFocus ? 20 : 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(
                    Icons.search,
                    color: _hasFocus ? AppTheme.primary : AppTheme.textMuted,
                    size: 22,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: false, // Prevents keyboard opening on startup
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 16),
                    decoration: const InputDecoration(
                      hintText: 'Where to?',
                      hintStyle:
                          TextStyle(color: AppTheme.textMuted, fontSize: 15),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 15),
                    ),
                    onChanged: _search,
                  ),
                ),
                if (_isSearching)
                  const Padding(
                    padding: EdgeInsets.only(right: 14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primary),
                    ),
                  )
                else if (_controller.text.isNotEmpty || _hasFocus)
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppTheme.textMuted, size: 20),
                    onPressed: _clear,
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.local_shipping,
                        color: AppTheme.primary, size: 20),
                  ),
              ],
            ),
          ),

          // ── Suggestions dropdown ─────────────────────────────────────────
          if (_hasFocus && _suggestions.isNotEmpty)
            FadeTransition(
              opacity: _fadeAnim,
              child: Container(
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: AppTheme.bg2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF252535)),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black54,
                        blurRadius: 20,
                        offset: Offset(0, 4))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _suggestions.length,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    separatorBuilder: (_, __) => const Divider(
                        color: Color(0xFF252535), height: 1, indent: 52),
                    itemBuilder: (_, i) {
                      final s = _suggestions[i];
                      final parts =
                          (s['display_name'] as String? ?? '').split(',');
                      final title = parts.take(2).join(',').trim();
                      final subtitle = parts.skip(2).take(2).join(',').trim();
                      return ListTile(
                        onTap: () => _select(s),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        leading: Container(
                          width: 36,
                          height: 36,
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
                                    color: AppTheme.textMuted, fontSize: 11))
                            : null,
                        dense: true,
                      );
                    },
                  ),
                ),
              ),
            ),

          // ── Quick Filter Chips ─────────────────────────────────────────
          if (!_hasFocus && _suggestions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _QuickFilterChip(
                      icon: Icons.local_gas_station_rounded,
                      label: 'Fuel',
                      onTap: () {
                        _controller.text = 'Truck Stop';
                        _search('Truck Stop');
                        _focusNode.requestFocus();
                      },
                    ),
                    _QuickFilterChip(
                      icon: Icons.local_parking_rounded,
                      label: 'Parking',
                      onTap: () {
                        _controller.text = 'Truck Parking';
                        _search('Truck Parking');
                        _focusNode.requestFocus();
                      },
                    ),
                    _QuickFilterChip(
                      icon: Icons.monitor_weight_rounded,
                      label: 'Weigh Station',
                      onTap: () {
                        _controller.text = 'Weigh Station';
                        _search('Weigh Station');
                        _focusNode.requestFocus();
                      },
                    ),
                    _QuickFilterChip(
                      icon: Icons.fastfood_rounded,
                      label: 'Food',
                      onTap: () {
                        _controller.text = 'Restaurant';
                        _search('Restaurant');
                        _focusNode.requestFocus();
                      },
                    ),
                    _QuickFilterChip(
                      icon: Icons.park_rounded,
                      label: 'Rest Area',
                      onTap: () {
                        _controller.text = 'Rest Area';
                        _search('Rest Area');
                        _focusNode.requestFocus();
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Quick Filter Chip Widget ────────────────────────────────────────────────

class _QuickFilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickFilterChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.panelBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF252535)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.primary, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

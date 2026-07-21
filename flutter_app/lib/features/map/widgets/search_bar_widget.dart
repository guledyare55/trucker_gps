import 'package:flutter/material.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';

/// Destination search bar — tapping activates it; keyboard never auto-opens.
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
  bool _isExpanded = false; // Collapsed by default — no keyboard on startup
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _controller.text.isEmpty) {
        _collapse();
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

  void _expand() {
    setState(() => _isExpanded = true);
    _animCtrl.forward();
    // Small delay so the widget is built before requesting focus
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _collapse() {
    _focusNode.unfocus();
    _controller.clear();
    setState(() {
      _isExpanded = false;
      _suggestions = [];
    });
    _animCtrl.reverse();
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
    _collapse();
    widget.onDestinationSelected(LatLng(lat, lon), name);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Collapsed pill (tap to open) or expanded text field ──────────
          GestureDetector(
            onTap: _isExpanded ? null : _expand,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: AppTheme.panelBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _isExpanded
                      ? AppTheme.primary.withOpacity(0.6)
                      : const Color(0xFF252535),
                  width: _isExpanded ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isExpanded
                        ? AppTheme.primary.withOpacity(0.15)
                        : Colors.black38,
                    blurRadius: _isExpanded ? 20 : 12,
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
                      color: _isExpanded ? AppTheme.primary : AppTheme.textMuted,
                      size: 22,
                    ),
                  ),
                  Expanded(
                    child: _isExpanded
                        ? TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: false,
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 16),
                            decoration: const InputDecoration(
                              hintText: 'Search destination...',
                              hintStyle: TextStyle(
                                  color: AppTheme.textMuted, fontSize: 15),
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 15),
                            ),
                            onChanged: _search,
                          )
                        : const Padding(
                            padding: EdgeInsets.symmetric(vertical: 15),
                            child: Text(
                              'Where to?',
                              style: TextStyle(
                                  color: AppTheme.textMuted, fontSize: 15),
                            ),
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
                  else if (_isExpanded)
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: AppTheme.textMuted, size: 20),
                      onPressed: _collapse,
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
          ),

          // ── Suggestions dropdown ─────────────────────────────────────────
          if (_isExpanded && _suggestions.isNotEmpty)
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
                      final subtitle =
                          parts.skip(2).take(2).join(',').trim();
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
                                    color: AppTheme.textMuted,
                                    fontSize: 11))
                            : null,
                        dense: true,
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

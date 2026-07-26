import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';

/// Destination search bar — smart focus, 10-item history, scrollable 5-item view, voice search.
class SearchBarWidget extends StatefulWidget {
  final void Function(LatLng destination, String name) onDestinationSelected;
  final void Function(List<String> categories)? onFiltersChanged;

  const SearchBarWidget({
    super.key,
    required this.onDestinationSelected,
    this.onFiltersChanged,
  });

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final Dio _dio = Dio();
  final SpeechToText _speechToText = SpeechToText();

  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _history = [];
  final Set<String> _activeFilters = {};
  bool _isSearching = false;
  bool _hasFocus = false;
  bool _speechEnabled = false;
  bool _isListening = false;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);

    _loadHistory();
    _initSpeech();

    _focusNode.addListener(() {
      setState(() => _hasFocus = _focusNode.hasFocus);
      if (_hasFocus) {
        if (_controller.text.isEmpty && _history.isNotEmpty) {
          setState(() => _suggestions = _history);
        }
        _animCtrl.forward();
      } else {
        if (_controller.text.isEmpty) {
          setState(() => _suggestions = []);
        }
        _animCtrl.reverse();
      }
    });
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speechToText.initialize(
        onError: (_) => setState(() => _isListening = false),
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
      );
      if (mounted) {
        setState(() => _speechEnabled = available);
      }
    } catch (_) {}
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speechToText.stop();
      setState(() => _isListening = false);
      return;
    }

    if (!_speechEnabled) {
      _initSpeech();
    }

    setState(() {
      _isListening = true;
      _hasFocus = true;
    });
    _focusNode.requestFocus();

    await _speechToText.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            _controller.text = result.recognizedWords;
          });
          _search(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('recent_searches_v1');
      if (jsonStr != null) {
        final List decoded = jsonDecode(jsonStr);
        if (mounted) {
          setState(() {
            _history = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveHistoryItem(Map<String, dynamic> item) async {
    try {
      final name = item['display_name'] ?? '';
      _history.removeWhere((h) => (h['display_name'] ?? '') == name);
      _history.insert(0, {
        'display_name': name,
        'lat': item['lat']?.toString() ?? '0',
        'lon': item['lon']?.toString() ?? '0',
        'isHistory': true,
      });
      if (_history.length > 10) {
        _history = _history.sublist(0, 10);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('recent_searches_v1', jsonEncode(_history));
    } catch (_) {}
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

  void _toggleFilter(String category) {
    setState(() {
      if (_activeFilters.contains(category)) {
        _activeFilters.remove(category);
      } else {
        _activeFilters.add(category);
      }
    });
    widget.onFiltersChanged?.call(_activeFilters.toList());
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _suggestions = _history);
      return;
    }
    if (query.length < 2) {
      return;
    }
    setState(() => _isSearching = true);
    try {
      final response = await _dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'json',
          'limit': 10,
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
    final lat = double.tryParse(s['lat']?.toString() ?? '0') ?? 0;
    final lon = double.tryParse(s['lon']?.toString() ?? '0') ?? 0;
    final name = s['display_name'] ?? '';
    _saveHistoryItem(s);
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
                    ? AppTheme.primary.withValues(alpha: 0.6)
                    : const Color(0xFF252535),
                width: _hasFocus ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _hasFocus
                      ? AppTheme.primary.withValues(alpha: 0.15)
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
                    autofocus: false,
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
                // Voice Search Microphone Button
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none_rounded,
                    color: _isListening ? Colors.redAccent : (_hasFocus ? AppTheme.primary : AppTheme.textMuted),
                    size: 22,
                  ),
                  tooltip: _isListening ? 'Listening...' : 'Voice Search',
                  onPressed: _toggleListening,
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

          // ── Suggestions / History dropdown (Max 5 visible, scrollable to 10) ──
          if (_hasFocus && _suggestions.isNotEmpty)
            FadeTransition(
              opacity: _fadeAnim,
              child: Container(
                margin: const EdgeInsets.only(top: 6),
                constraints: const BoxConstraints(maxHeight: 280), // Shows 5 items, scrollable for rest
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
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: _suggestions.length,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      separatorBuilder: (_, __) => const Divider(
                          color: Color(0xFF252535), height: 1, indent: 52),
                      itemBuilder: (_, i) {
                        final s = _suggestions[i];
                        final isHist = s['isHistory'] == true;
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
                              color: isHist
                                  ? const Color(0xFF2A2A3C)
                                  : AppTheme.bg3,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isHist ? Icons.history : Icons.location_on,
                              color: isHist ? Colors.amber : AppTheme.primary,
                              size: 18,
                            ),
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
                              : (isHist
                                  ? const Text('Recent Search',
                                      style: TextStyle(
                                          color: Colors.amber, fontSize: 11))
                                  : null),
                          dense: true,
                        );
                      },
                    ),
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
                      icon: Icons.local_parking_rounded, // or maybe local_shipping
                      label: 'Truck Stop',
                      isActive: _activeFilters.contains('Truck Stop'),
                      onTap: () => _toggleFilter('Truck Stop'),
                    ),
                    _QuickFilterChip(
                      icon: Icons.local_gas_station_rounded,
                      label: 'Fuel',
                      isActive: _activeFilters.contains('Fuel'),
                      onTap: () => _toggleFilter('Fuel'),
                    ),
                    _QuickFilterChip(
                      icon: Icons.monitor_weight_rounded,
                      label: 'Weigh Station',
                      isActive: _activeFilters.contains('Weigh Station'),
                      onTap: () => _toggleFilter('Weigh Station'),
                    ),
                    _QuickFilterChip(
                      icon: Icons.fastfood_rounded,
                      label: 'Food',
                      isActive: _activeFilters.contains('Food'),
                      onTap: () => _toggleFilter('Food'),
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
  final bool isActive;
  final VoidCallback onTap;

  const _QuickFilterChip({
    required this.icon,
    required this.label,
    this.isActive = false,
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
          color: isActive ? AppTheme.primary.withOpacity(0.15) : AppTheme.panelBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? AppTheme.primary : const Color(0xFF252535)),
          boxShadow: [
            if (isActive)
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            else
              const BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? AppTheme.primary : AppTheme.textMuted, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppTheme.primary : AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

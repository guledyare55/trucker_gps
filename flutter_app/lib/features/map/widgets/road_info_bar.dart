import 'package:flutter/material.dart';

/// Displays the current road name / highway number above the bottom nav bar.
/// Shows an Interstate shield, US route sign, or a generic pill depending on
/// the OSM `ref` value (e.g. "I 24", "US 64", "SR 396").
class RoadInfoBar extends StatelessWidget {
  final String roadRef;
  final String roadName;

  const RoadInfoBar({super.key, required this.roadRef, required this.roadName});

  @override
  Widget build(BuildContext context) {
    if (roadRef.isEmpty && roadName.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: const Color(0x99000000),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (roadRef.isNotEmpty) ...[
            _buildShield(roadRef),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              roadName.isNotEmpty ? roadName : _formatRef(roadRef),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShield(String ref) {
    final type = _detectShieldType(ref);
    final number = _extractNumber(ref);
    switch (type) {
      case _ShieldType.interstate:
        return _InterstateShield(number: number);
      case _ShieldType.usRoute:
        return _USRouteShield(number: number);
      case _ShieldType.stateRoute:
        return _StateRouteShield(number: number);
      case _ShieldType.none:
        return const SizedBox.shrink();
    }
  }

  _ShieldType _detectShieldType(String ref) {
    final upper = ref.toUpperCase();
    if (upper.startsWith('I ') || upper.startsWith('I-')) return _ShieldType.interstate;
    if (upper.startsWith('US ') || upper.startsWith('US-')) return _ShieldType.usRoute;
    if (upper.startsWith('SR ') || upper.startsWith('STATE ') ||
        RegExp(r'^[A-Z]{2}[\s\-]?\d').hasMatch(upper)) return _ShieldType.stateRoute;
    return _ShieldType.none;
  }

  String _extractNumber(String ref) => ref.replaceAll(RegExp(r'[^0-9]'), '');
  String _formatRef(String ref) => ref.replaceAll('-', ' ');
}

enum _ShieldType { interstate, usRoute, stateRoute, none }

// ── Interstate Shield ─────────────────────────────────────────────────────────

class _InterstateShield extends StatelessWidget {
  final String number;
  const _InterstateShield({required this.number});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(32, 36),
      painter: _InterstateShieldPainter(),
      child: SizedBox(
        width: 32,
        height: 36,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              number,
              style: TextStyle(
                color: Colors.white,
                fontSize: number.length > 2 ? 9 : 11,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InterstateShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Pentagon body (blue)
    final bodyPath = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.35)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..lineTo(0, h * 0.35)
      ..close();
    canvas.drawPath(bodyPath, Paint()..color = const Color(0xFF003399));

    // Red top banner
    final redPath = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.35)
      ..lineTo(w, h * 0.42)
      ..lineTo(0, h * 0.42)
      ..lineTo(0, h * 0.35)
      ..close();
    canvas.drawPath(redPath, Paint()..color = const Color(0xFFCC0000));

    // White border
    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── US Route Shield ───────────────────────────────────────────────────────────

class _USRouteShield extends StatelessWidget {
  final String number;
  const _USRouteShield({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Center(
        child: Text(
          number,
          style: TextStyle(
            color: Colors.black,
            fontSize: number.length > 2 ? 8 : 10,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

// ── State Route Shield ────────────────────────────────────────────────────────

class _StateRouteShield extends StatelessWidget {
  final String number;
  const _StateRouteShield({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: Text(
        number,
        style: TextStyle(
          color: Colors.black,
          fontSize: number.length > 2 ? 8 : 10,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

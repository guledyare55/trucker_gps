import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

class AppPermissions {
  static Future<bool> requestLocation() async {
    if (kIsWeb) return true; // Handled by browser natively via geolocator
    
    final status = await Permission.location.request();
    return status.isGranted;
  }
}

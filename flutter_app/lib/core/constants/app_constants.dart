import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'TruckerGPS';
  
  // Base URLs (Point to your Python backend)
  // Use 10.0.2.2 for Android emulator pointing to localhost
  // Use localhost for iOS simulator
  static const String apiBaseUrl = 'http://10.0.2.2:8000/api/v1';
  static const String wsBaseUrl = 'ws://10.0.2.2:8000/api/v1/fleet/ws';

  // Map settings
  static const double defaultZoom = 15.0;
  static const double minZoom = 3.0;
  static const double maxZoom = 22.0;
  
  // Storage keys
  static const String truckProfileKey = 'truck_profile';
  static const String settingsKey = 'app_settings';
  static const String recentTripsKey = 'recent_trips';
}

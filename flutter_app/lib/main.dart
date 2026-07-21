import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trucker_gps/core/theme/app_theme.dart';
import 'package:trucker_gps/features/map/screens/map_screen.dart';
import 'package:trucker_gps/core/constants/app_constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive or other storage here
  
  runApp(
    const ProviderScope(
      child: TruckerGPSApp(),
    ),
  );
}

class TruckerGPSApp extends ConsumerWidget {
  const TruckerGPSApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const MapScreen(),
    );
  }
}

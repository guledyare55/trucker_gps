import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trucker_gps/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('TruckerGPSApp smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const TruckerGPSApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

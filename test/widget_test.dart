import 'package:chat_app/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ThemeProvider toggles and persists mode', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final provider = ThemeProvider();
    await tester.pump();

    await provider.toggleTheme();
    expect(provider.themeMode, ThemeMode.dark);

    await provider.toggleTheme();
    expect(provider.themeMode, ThemeMode.light);
  });
}

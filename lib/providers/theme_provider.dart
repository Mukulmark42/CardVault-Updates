import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeProvider extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadTheme();
  }

  void toggleTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    _storage.write(key: 'isDarkMode', value: isDark.toString());
    notifyListeners();
  }

  Future<void> _loadTheme() async {
    String? isDarkStr = await _storage.read(key: 'isDarkMode');
    if (isDarkStr != null) {
      _themeMode = isDarkStr == 'true' ? ThemeMode.dark : ThemeMode.light;
      notifyListeners();
    }
  }
}

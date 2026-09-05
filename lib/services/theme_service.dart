import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'sync_service.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService instance = ThemeService._init();

  ThemeMode _themeMode = ThemeMode.dark;
  String? _loadedProfileName;

  ThemeService._init();

  ThemeMode get themeMode => _themeMode;
  String? get loadedProfileName => _loadedProfileName;

  String get themeModeString {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.dark:
        return 'dark';
    }
  }

  /// Evaluates whether dark mode is currently active given context (resolves ThemeMode.system)
  bool isDarkMode(BuildContext context) {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  /// Loads the theme mode stored for the specified or currently active profile
  Future<void> loadThemeForProfile([String? profileName]) async {
    try {
      final name = profileName ?? await DatabaseHelper.instance.getActiveProfileName();
      _loadedProfileName = name;
      final db = await DatabaseHelper.instance.database;
      final res = await db.query(
        'profiles',
        columns: ['theme_mode'],
        where: 'name = ?',
        whereArgs: [name],
        limit: 1,
      );

      if (res.isNotEmpty && res.first['theme_mode'] != null) {
        final modeStr = res.first['theme_mode'] as String;
        _themeMode = _parseThemeMode(modeStr);
      } else {
        _themeMode = ThemeMode.dark;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('ThemeService: Error loading theme: $e');
    }
  }

  /// Sets the theme mode, immediately updates listeners, and persists to the profile in SQLite
  Future<void> setThemeMode(ThemeMode mode, {String? profileName, bool syncRemote = true}) async {
    _themeMode = mode;
    notifyListeners();

    try {
      final name = profileName ?? _loadedProfileName ?? await DatabaseHelper.instance.getActiveProfileName();
      _loadedProfileName = name;
      final db = await DatabaseHelper.instance.database;
      final modeStr = themeModeString;

      await db.update(
        'profiles',
        {
          'theme_mode': modeStr,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'name = ?',
        whereArgs: [name],
      );

      if (syncRemote) {
        SyncService.instance.signInAndSync();
      }
    } catch (e) {
      debugPrint('ThemeService: Error persisting theme: $e');
    }
  }

  /// Sets theme mode from string ('dark', 'light', 'system')
  Future<void> setThemeModeFromString(String modeStr, {String? profileName, bool syncRemote = true}) async {
    final mode = _parseThemeMode(modeStr);
    await setThemeMode(mode, profileName: profileName, syncRemote: syncRemote);
  }

  ThemeMode _parseThemeMode(String modeStr) {
    switch (modeStr.toLowerCase().trim()) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:emom_timer_flutter/services/database_helper.dart';
import 'package:emom_timer_flutter/services/theme_service.dart';
import 'package:emom_timer_flutter/theme/app_colors.dart';
import 'package:emom_timer_flutter/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Theme System Tests', () {
    test('AppColors defines dark and light theme tokens', () {
      expect(AppColors.deepBg, const Color(0xFF0C101B));
      expect(AppColors.lightBg, const Color(0xFFF4F6F9));
      expect(AppColors.lightSurface, const Color(0xFFFFFFFF));
      expect(AppColors.lightTextPrimary, const Color(0xFF0F172A));
      expect(AppColors.mintLightPrimary, const Color(0xFF059669));
      expect(AppColors.orangeLightSecondary, const Color(0xFFD97706));
    });

    test('AppTheme creates valid ThemeData for dark and light modes', () {
      final darkTheme = AppTheme.darkTheme;
      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.scaffoldBackgroundColor, AppColors.deepBg);
      expect(darkTheme.colorScheme.primary, AppColors.mintNeon);

      final lightTheme = AppTheme.lightTheme;
      expect(lightTheme.brightness, Brightness.light);
      expect(lightTheme.scaffoldBackgroundColor, AppColors.lightBg);
      expect(lightTheme.colorScheme.primary, AppColors.mintLightPrimary);
      expect(lightTheme.colorScheme.onSurface, AppColors.lightTextPrimary);
    });

    test('ThemeService updates theme mode and notifies listeners', () async {
      final service = ThemeService.instance;
      int notifications = 0;
      void listener() => notifications++;

      service.addListener(listener);

      await service.setThemeMode(ThemeMode.light, profileName: 'TestProfile', syncRemote: false);
      expect(service.themeMode, ThemeMode.light);
      expect(service.themeModeString, 'light');
      expect(notifications, greaterThanOrEqualTo(1));

      await service.setThemeMode(ThemeMode.system, profileName: 'TestProfile', syncRemote: false);
      expect(service.themeMode, ThemeMode.system);
      expect(service.themeModeString, 'system');

      await service.setThemeMode(ThemeMode.dark, profileName: 'TestProfile', syncRemote: false);
      expect(service.themeMode, ThemeMode.dark);
      expect(service.themeModeString, 'dark');

      service.removeListener(listener);
    });
  });

  group('Database Theme Migration and Persistence Tests', () {
    late String dbPath;
    late Database testDb;

    Future<void> deleteDbFile() async {
      try {
        final file = File(dbPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    setUp(() async {
      final dbDir = await databaseFactory.getDatabasesPath();
      dbPath = p.join(dbDir, 'test_theme_db.db');
      await deleteDbFile();

      // Open database using DatabaseHelper schema
      testDb = await openDatabase(
        dbPath,
        version: 20,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
                name TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                max_hr INTEGER,
                max_prework_hr INTEGER,
                sex TEXT,
                birth_date TEXT,
                weight_kg REAL,
                weight_unit_pref TEXT,
                distance_unit_pref TEXT DEFAULT 'km',
                auto_connect_hr INTEGER,
                health_enabled INTEGER DEFAULT 0,
                save_history INTEGER DEFAULT 1,
                treadmill_enabled INTEGER DEFAULT 0,
                treadmill_preset_1 REAL DEFAULT 2.0,
                treadmill_preset_2 REAL DEFAULT 4.0,
                treadmill_preset_3 REAL DEFAULT 6.0,
                theme_mode TEXT DEFAULT 'dark',
                updated_at TEXT
            )
          ''');
        },
      );
      DatabaseHelper.instance.setDatabaseForTesting(testDb);
    });

    tearDown(() async {
      await testDb.close();
      await deleteDbFile();
    });

    test('profiles table has theme_mode column with default "dark"', () async {
      await testDb.insert('profiles', {
        'name': 'Default',
        'created_at': DateTime.now().toIso8601String(),
      });

      final rows = await testDb.query('profiles', where: 'name = ?', whereArgs: ['Default']);
      expect(rows.length, 1);
      expect(rows.first['theme_mode'], 'dark');
    });

    test('theme_mode can be updated and queried per profile', () async {
      await testDb.insert('profiles', {
        'name': 'AthleteA',
        'created_at': DateTime.now().toIso8601String(),
        'theme_mode': 'dark',
      });
      await testDb.insert('profiles', {
        'name': 'AthleteB',
        'created_at': DateTime.now().toIso8601String(),
        'theme_mode': 'light',
      });

      // Load theme for AthleteB
      await ThemeService.instance.loadThemeForProfile('AthleteB');
      expect(ThemeService.instance.themeMode, ThemeMode.light);

      // Load theme for AthleteA
      await ThemeService.instance.loadThemeForProfile('AthleteA');
      expect(ThemeService.instance.themeMode, ThemeMode.dark);

      // Change AthleteA to light
      await ThemeService.instance.setThemeMode(ThemeMode.light, profileName: 'AthleteA', syncRemote: false);
      expect(ThemeService.instance.themeMode, ThemeMode.light);

      final row = await testDb.query('profiles', where: 'name = ?', whereArgs: ['AthleteA']);
      expect(row.first['theme_mode'], 'light');
    });

    test('migration from v19 to v20 adds theme_mode column without data loss', () async {
      await testDb.close();
      await deleteDbFile();

      // Create v19 database
      final oldDb = await openDatabase(
        dbPath,
        version: 19,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
                name TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                max_hr INTEGER,
                theme_mode TEXT DEFAULT 'dark',
                updated_at TEXT
            )
          ''');
        },
      );
      await oldDb.close();

      // Re-create pure v19 without theme_mode column to simulate existing user DB
      await deleteDbFile();
      final v19Db = await openDatabase(
        dbPath,
        version: 19,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
                name TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                max_hr INTEGER,
                updated_at TEXT
            )
          ''');
          await db.insert('profiles', {
            'name': 'ExistingUser',
            'created_at': '2026-01-01T00:00:00.000',
            'max_hr': 185,
          });
        },
      );
      await v19Db.close();

      // Upgrade to v20
      final upgradedDb = await openDatabase(
        dbPath,
        version: 20,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 20) {
            await db.execute("ALTER TABLE profiles ADD COLUMN theme_mode TEXT DEFAULT 'dark'");
          }
        },
      );

      final userRow = await upgradedDb.query('profiles', where: 'name = ?', whereArgs: ['ExistingUser']);
      expect(userRow.length, 1);
      expect(userRow.first['max_hr'], 185);
      expect(userRow.first['theme_mode'], 'dark');

      await upgradedDb.close();
    });
  });
}

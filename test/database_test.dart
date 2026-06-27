import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() {
  // Initialize FFI for tests
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Database Schema and Migration Tests', () {
    late String dbPath;

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
      dbPath = p.join(dbDir, 'test_db_migration.db');
      await deleteDbFile();
    });

    tearDown(() async {
      await deleteDbFile();
    });

    test('Create DB version 3 contains workout_name column', () async {
      final db = await openDatabase(
        dbPath,
        version: 3,
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
                auto_connect_hr INTEGER
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS workout_templates (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_name TEXT,
                template_name TEXT,
                rounds INTEGER,
                work_time INTEGER,
                rest_time INTEGER,
                notes TEXT,
                continuous_mode INTEGER DEFAULT 0,
                FOREIGN KEY(profile_name) REFERENCES profiles(name) ON DELETE CASCADE,
                UNIQUE(profile_name, template_name)
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS workouts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_name TEXT,
                workout_name TEXT,
                start_time TEXT NOT NULL,
                end_time TEXT,
                total_rounds_completed INTEGER,
                work_duration INTEGER,
                rest_duration INTEGER,
                total_time_sec INTEGER,
                work_time_sec INTEGER,
                rest_time_sec INTEGER,
                max_hr INTEGER,
                avg_hr INTEGER,
                calories_burnt_kcal REAL,
                notes TEXT,
                details_file_legacy TEXT,
                FOREIGN KEY(profile_name) REFERENCES profiles(name) ON DELETE CASCADE
            )
          ''');
        },
      );

      // Insert a mock profile and workout record with a custom name
      await db.insert('profiles', {
        'name': 'Default',
        'created_at': DateTime.now().toIso8601String(),
      });

      await db.insert('workouts', {
        'profile_name': 'Default',
        'workout_name': 'ABC - Double 18KG',
        'start_time': '2026-06-20T12:00:00',
        'total_rounds_completed': 10,
        'work_duration': 60,
        'rest_duration': 30,
        'total_time_sec': 900,
        'work_time_sec': 600,
        'rest_time_sec': 300,
        'max_hr': 150,
        'avg_hr': 130,
        'calories_burnt_kcal': 120.5,
        'notes': 'Test notes',
      });

      // Query the workout and verify workout_name
      final res = await db.query('workouts');
      expect(res.length, equals(1));
      expect(res.first['workout_name'], equals('ABC - Double 18KG'));

      await db.close();
    });

    test('Migration from version 2 to 3 adds workout_name column successfully', () async {
      // 1. Create a version 2 database schema (no workout_name column in workouts)
      final db = await openDatabase(
        dbPath,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
                name TEXT PRIMARY KEY,
                created_at TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS workouts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_name TEXT,
                start_time TEXT NOT NULL,
                end_time TEXT,
                total_rounds_completed INTEGER,
                work_duration INTEGER,
                rest_duration INTEGER,
                total_time_sec INTEGER,
                work_time_sec INTEGER,
                rest_time_sec INTEGER,
                max_hr INTEGER,
                avg_hr INTEGER,
                calories_burnt_kcal REAL,
                notes TEXT,
                details_file_legacy TEXT,
                FOREIGN KEY(profile_name) REFERENCES profiles(name) ON DELETE CASCADE
            )
          ''');
        },
      );

      // Insert a profile and workout under version 2 schema
      await db.insert('profiles', {
        'name': 'Default',
        'created_at': DateTime.now().toIso8601String(),
      });

      await db.insert('workouts', {
        'profile_name': 'Default',
        'start_time': '2026-06-20T12:00:00',
        'total_rounds_completed': 5,
        'work_duration': 60,
        'rest_duration': 30,
      });

      await db.close();

      // 2. Open it again with version 3 triggering the migration
      final dbV3 = await openDatabase(
        dbPath,
        version: 3,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 3) {
            await db.execute('ALTER TABLE workouts ADD COLUMN workout_name TEXT');
          }
        },
      );

      // Verify that we can query and update the workout_name column on the migrated database
      await dbV3.update(
        'workouts',
        {'workout_name': 'ABC - Double 18KG'},
        where: 'id = ?',
        whereArgs: [1],
      );

      final res = await dbV3.query('workouts');
      expect(res.first['workout_name'], equals('ABC - Double 18KG'));

      await dbV3.close();
    });

    test('Create DB version 4 contains health_enabled column in profiles', () async {
      final db = await openDatabase(
        dbPath,
        version: 4,
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
                auto_connect_hr INTEGER,
                health_enabled INTEGER DEFAULT 0
            )
          ''');
        },
      );

      await db.insert('profiles', {
        'name': 'Default',
        'created_at': DateTime.now().toIso8601String(),
        'health_enabled': 1,
      });

      final res = await db.query('profiles');
      expect(res.length, equals(1));
      expect(res.first['health_enabled'], equals(1));

      await db.close();
    });

    test('Migration from version 3 to 4 adds health_enabled column to profiles', () async {
      // 1. Create a version 3 database schema
      final db = await openDatabase(
        dbPath,
        version: 3,
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
                auto_connect_hr INTEGER
            )
          ''');
        },
      );

      await db.insert('profiles', {
        'name': 'Default',
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.close();

      // 2. Open it with version 4 to trigger the upgrade
      final dbV4 = await openDatabase(
        dbPath,
        version: 4,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 4) {
            await db.execute('ALTER TABLE profiles ADD COLUMN health_enabled INTEGER DEFAULT 0');
          }
        },
      );

      // Verify and update health_enabled
      await dbV4.update(
        'profiles',
        {'health_enabled': 1},
        where: 'name = ?',
        whereArgs: ['Default'],
      );

      final res = await dbV4.query('profiles');
      expect(res.first['health_enabled'], equals(1));

      await dbV4.close();
    });

    test('Create DB version 5 contains activity_type in templates and workouts', () async {
      final db = await openDatabase(
        dbPath,
        version: 5,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workout_templates (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                template_name TEXT,
                activity_type TEXT DEFAULT 'HIIT'
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workouts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workout_name TEXT,
                activity_type TEXT DEFAULT 'HIIT'
            )
          ''');
        },
      );

      await db.insert('workout_templates', {
        'template_name': 'My Template',
        'activity_type': 'STRENGTH',
      });
      await db.insert('workouts', {
        'workout_name': 'My Workout',
        'activity_type': 'CARDIO',
      });

      final templates = await db.query('workout_templates');
      expect(templates.length, equals(1));
      expect(templates.first['activity_type'], equals('STRENGTH'));

      final workouts = await db.query('workouts');
      expect(workouts.length, equals(1));
      expect(workouts.first['activity_type'], equals('CARDIO'));

      await db.close();
    });

    test('Migration from version 4 to 5 adds activity_type columns', () async {
      // 1. Create a version 4 database schema
      final db = await openDatabase(
        dbPath,
        version: 4,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workout_templates (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                template_name TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workouts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workout_name TEXT
            )
          ''');
        },
      );

      await db.insert('workout_templates', {'template_name': 'Legacy Template'});
      await db.insert('workouts', {'workout_name': 'Legacy Workout'});
      await db.close();

      // 2. Open it with version 5 to trigger the upgrade
      final dbV5 = await openDatabase(
        dbPath,
        version: 5,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 5) {
            await db.execute("ALTER TABLE workout_templates ADD COLUMN activity_type TEXT DEFAULT 'HIIT'");
            await db.execute("ALTER TABLE workouts ADD COLUMN activity_type TEXT DEFAULT 'HIIT'");
          }
        },
      );

      // Verify and update
      await dbV5.update(
        'workout_templates',
        {'activity_type': 'STRENGTH'},
        where: 'id = ?',
        whereArgs: [1],
      );

      final templates = await dbV5.query('workout_templates');
      expect(templates.first['activity_type'], equals('STRENGTH'));

      final workouts = await dbV5.query('workouts');
      expect(workouts.first['activity_type'], equals('HIIT')); // defaults to HIIT

      await dbV5.close();
    });

    test('Create DB version 6 contains save_history in profiles', () async {
      final db = await openDatabase(
        dbPath,
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
                name TEXT PRIMARY KEY,
                save_history INTEGER DEFAULT 1
            )
          ''');
        },
      );

      await db.insert('profiles', {
        'name': 'Test User',
        'save_history': 0,
      });

      final profiles = await db.query('profiles');
      expect(profiles.length, equals(1));
      expect(profiles.first['save_history'], equals(0));

      await db.close();
    });

    test('Migration from version 5 to 6 adds save_history to profiles', () async {
      final db = await openDatabase(
        dbPath,
        version: 5,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
                name TEXT PRIMARY KEY
            )
          ''');
        },
      );

      await db.insert('profiles', {'name': 'Legacy Profile'});
      await db.close();

      final dbV6 = await openDatabase(
        dbPath,
        version: 6,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 6) {
            await db.execute('ALTER TABLE profiles ADD COLUMN save_history INTEGER DEFAULT 1');
          }
        },
      );

      final profiles = await dbV6.query('profiles');
      expect(profiles.first['save_history'], equals(1)); // defaults to 1

      await dbV6.close();
    });

    test('Create DB version 7 contains auto_regulate in workout_templates', () async {
      final db = await openDatabase(
        dbPath,
        version: 7,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workout_templates (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                template_name TEXT,
                auto_regulate INTEGER DEFAULT 1
            )
          ''');
        },
      );

      await db.insert('workout_templates', {
        'template_name': 'Test Workout',
        'auto_regulate': 0,
      });

      final templates = await db.query('workout_templates');
      expect(templates.length, equals(1));
      expect(templates.first['auto_regulate'], equals(0));

      await db.close();
    });

    test('Migration from version 6 to 7 adds auto_regulate to workout_templates', () async {
      final db = await openDatabase(
        dbPath,
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workout_templates (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                template_name TEXT
            )
          ''');
        },
      );

      await db.insert('workout_templates', {'template_name': 'Legacy Workout'});
      await db.close();

      final dbV7 = await openDatabase(
        dbPath,
        version: 7,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 7) {
            await db.execute('ALTER TABLE workout_templates ADD COLUMN auto_regulate INTEGER DEFAULT 1');
          }
        },
      );

      final templates = await dbV7.query('workout_templates');
      expect(templates.first['auto_regulate'], equals(1)); // defaults to 1

      await dbV7.close();
    });
  });
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:emom_timer_flutter/services/database_helper.dart';
import 'package:emom_timer_flutter/services/hrr_service.dart';

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

    test('Migration from version 7 to 8 adds treadmill profiles fields successfully', () async {
      final db = await openDatabase(
        dbPath,
        version: 7,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
                name TEXT PRIMARY KEY,
                created_at TEXT NOT NULL
            )
          ''');
        },
      );

      await db.insert('profiles', {'name': 'Test User', 'created_at': '2026-06-20'});
      await db.close();

      final dbV8 = await openDatabase(
        dbPath,
        version: 8,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 8) {
            await db.execute('ALTER TABLE profiles ADD COLUMN treadmill_enabled INTEGER DEFAULT 0');
            await db.execute('ALTER TABLE profiles ADD COLUMN treadmill_preset_1 REAL DEFAULT 2.0');
            await db.execute('ALTER TABLE profiles ADD COLUMN treadmill_preset_2 REAL DEFAULT 4.0');
            await db.execute('ALTER TABLE profiles ADD COLUMN treadmill_preset_3 REAL DEFAULT 6.0');
          }
        },
      );

      final profiles = await dbV8.query('profiles');
      expect(profiles.first['treadmill_enabled'], equals(0));
      expect(profiles.first['treadmill_preset_1'], equals(2.0));
      expect(profiles.first['treadmill_preset_2'], equals(4.0));
      expect(profiles.first['treadmill_preset_3'], equals(6.0));

      await dbV8.close();
    });

    test('Migration from version 8 to 9 adds treadmill template fields successfully', () async {
      final db = await openDatabase(
        dbPath,
        version: 8,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workout_templates (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                template_name TEXT
            )
          ''');
        },
      );

      await db.insert('workout_templates', {'template_name': 'Sample Temp'});
      await db.close();

      final dbV9 = await openDatabase(
        dbPath,
        version: 9,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 9) {
            await db.execute('ALTER TABLE workout_templates ADD COLUMN treadmill_workout INTEGER DEFAULT 0');
            await db.execute('ALTER TABLE workout_templates ADD COLUMN work_speed REAL DEFAULT 4.0');
            await db.execute('ALTER TABLE workout_templates ADD COLUMN rest_speed REAL DEFAULT 0.0');
          }
        },
      );

      final templates = await dbV9.query('workout_templates');
      expect(templates.first['treadmill_workout'], equals(0));
      expect(templates.first['work_speed'], equals(4.0));
      expect(templates.first['rest_speed'], equals(0.0));

      await dbV9.close();
    });

    test('Migration from version 9 to 10 adds treadmill workouts fields successfully', () async {
      final db = await openDatabase(
        dbPath,
        version: 9,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workouts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_time TEXT NOT NULL
            )
          ''');
        },
      );

      await db.insert('workouts', {'start_time': '2026-06-20T12:00:00'});
      await db.close();

      final dbV10 = await openDatabase(
        dbPath,
        version: 10,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 10) {
            await db.execute('ALTER TABLE workouts ADD COLUMN run_distance REAL DEFAULT 0.0');
            await db.execute('ALTER TABLE workouts ADD COLUMN run_peak_speed REAL DEFAULT 0.0');
            await db.execute('ALTER TABLE workouts ADD COLUMN run_avg_speed REAL DEFAULT 0.0');
          }
        },
      );

      final workouts = await dbV10.query('workouts');
      expect(workouts.first['run_distance'], equals(0.0));
      expect(workouts.first['run_peak_speed'], equals(0.0));
      expect(workouts.first['run_avg_speed'], equals(0.0));

      await dbV10.close();
    });

    test('Migration from version 10 to 11 adds distance_unit_pref to profiles successfully', () async {
      final dbPath = '${await getDatabasesPath()}/migration_v10_to_v11.db';
      await deleteDatabase(dbPath);

      final db = await openDatabase(
        dbPath,
        version: 10,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
                name TEXT PRIMARY KEY,
                created_at TEXT NOT NULL
            )
          ''');
        },
      );

      await db.insert('profiles', {'name': 'Default', 'created_at': '2026-06-20T12:00:00'});
      await db.close();

      final dbV11 = await openDatabase(
        dbPath,
        version: 11,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 11) {
            await db.execute("ALTER TABLE profiles ADD COLUMN distance_unit_pref TEXT DEFAULT 'km'");
          }
        },
      );

      final profiles = await dbV11.query('profiles');
      expect(profiles.first['distance_unit_pref'], equals('km'));

      await dbV11.close();
    });

    test('Migration from version 11 to 12 adds updated_at to profiles successfully', () async {
      final dbPath = '${await getDatabasesPath()}/migration_v11_to_v12.db';
      await deleteDatabase(dbPath);

      final db = await openDatabase(
        dbPath,
        version: 11,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
                name TEXT PRIMARY KEY,
                created_at TEXT NOT NULL
            )
          ''');
        },
      );

      await db.insert('profiles', {'name': 'Default', 'created_at': '2026-06-20T12:00:00'});
      await db.close();

      final dbV12 = await openDatabase(
        dbPath,
        version: 12,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 12) {
            await db.execute("ALTER TABLE profiles ADD COLUMN updated_at TEXT");
          }
        },
      );

      final profiles = await dbV12.query('profiles');
      expect(profiles.first.containsKey('updated_at'), isTrue);

      await dbV12.close();
    });

    test('Migration from version 12 to 13 adds weight columns successfully', () async {
      final dbPath = '${await getDatabasesPath()}/migration_v12_to_v13.db';
      await deleteDatabase(dbPath);

      final db = await openDatabase(
        dbPath,
        version: 12,
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

      await db.insert('workout_templates', {'template_name': 'Strength Template'});
      await db.insert('workouts', {'workout_name': 'Strength Session'});
      await db.close();

      final dbV13 = await openDatabase(
        dbPath,
        version: 13,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 13) {
            await db.execute('ALTER TABLE workout_templates ADD COLUMN weight_moved REAL DEFAULT 0.0');
            await db.execute("ALTER TABLE workout_templates ADD COLUMN weight_unit TEXT DEFAULT 'kg'");
            await db.execute('ALTER TABLE workout_templates ADD COLUMN ruck_weight REAL DEFAULT 0.0');
            await db.execute("ALTER TABLE workout_templates ADD COLUMN ruck_weight_unit TEXT DEFAULT 'lbs'");
            
            await db.execute('ALTER TABLE workouts ADD COLUMN weight_moved REAL DEFAULT 0.0');
            await db.execute("ALTER TABLE workouts ADD COLUMN weight_unit TEXT DEFAULT 'kg'");
            await db.execute('ALTER TABLE workouts ADD COLUMN total_weight_moved REAL DEFAULT 0.0');
            await db.execute('ALTER TABLE workouts ADD COLUMN ruck_weight REAL DEFAULT 0.0');
            await db.execute("ALTER TABLE workouts ADD COLUMN ruck_weight_unit TEXT DEFAULT 'lbs'");
          }
        },
      );

      final templates = await dbV13.query('workout_templates');
      expect(templates.first['weight_moved'], equals(0.0));
      expect(templates.first['weight_unit'], equals('kg'));
      expect(templates.first['ruck_weight'], equals(0.0));
      expect(templates.first['ruck_weight_unit'], equals('lbs'));

      final workouts = await dbV13.query('workouts');
      expect(workouts.first['weight_moved'], equals(0.0));
      expect(workouts.first['weight_unit'], equals('kg'));
      expect(workouts.first['total_weight_moved'], equals(0.0));
      expect(workouts.first['ruck_weight'], equals(0.0));
      expect(workouts.first['ruck_weight_unit'], equals('lbs'));

      await dbV13.close();
    });

    test('Migration from version 13 to 14 adds reps_per_round columns successfully', () async {
      final dbPath = '${await getDatabasesPath()}/migration_v13_to_v14.db';
      await deleteDatabase(dbPath);

      final db = await openDatabase(
        dbPath,
        version: 13,
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

      await db.insert('workout_templates', {'template_name': 'Strength Template'});
      await db.insert('workouts', {'workout_name': 'Strength Session'});
      await db.close();

      final dbV14 = await openDatabase(
        dbPath,
        version: 14,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 14) {
            await db.execute('ALTER TABLE workout_templates ADD COLUMN reps_per_round INTEGER DEFAULT 1');
            await db.execute('ALTER TABLE workouts ADD COLUMN reps_per_round INTEGER DEFAULT 1');
          }
        },
      );

      final templates = await dbV14.query('workout_templates');
      expect(templates.first['reps_per_round'], equals(1));

      final workouts = await dbV14.query('workouts');
      expect(workouts.first['reps_per_round'], equals(1));

      await dbV14.close();
    });
  });

  group('DatabaseHelper Tonnage Tests', () {
    late String dbPath;
    late Database db;

    setUp(() async {
      final dbDir = await databaseFactory.getDatabasesPath();
      dbPath = p.join(dbDir, 'test_db_tonnage.db');
      try {
        await deleteDatabase(dbPath);
      } catch (_) {}
      
      // Initialize a test database matching schema version 15
      db = await openDatabase(
        dbPath,
        version: 15,
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
                updated_at TEXT
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
                activity_type TEXT DEFAULT 'HIIT',
                run_distance REAL DEFAULT 0.0,
                run_peak_speed REAL DEFAULT 0.0,
                run_avg_speed REAL DEFAULT 0.0,
                weight_moved REAL DEFAULT 0.0,
                weight_unit TEXT DEFAULT 'kg',
                total_weight_moved REAL DEFAULT 0.0,
                ruck_weight REAL DEFAULT 0.0,
                ruck_weight_unit TEXT DEFAULT 'lbs',
                reps_per_round INTEGER DEFAULT 1,
                reps_completed INTEGER DEFAULT 0,
                hrr_1min INTEGER,
                hrr_2min INTEGER,
                recovery_duration_sec INTEGER,
                FOREIGN KEY(profile_name) REFERENCES profiles(name) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS heart_rate_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workout_id INTEGER,
                capture_time TEXT,
                bpm INTEGER,
                zone TEXT,
                is_recovery INTEGER DEFAULT 0,
                FOREIGN KEY(workout_id) REFERENCES workouts(id) ON DELETE CASCADE
            )
          ''');
          
          await db.insert('profiles', {
            'name': 'Test User',
            'created_at': DateTime.now().toIso8601String(),
          });
        },
      );
      
      DatabaseHelper.instance.setDatabaseForTesting(db);
    });

    tearDown(() async {
      await db.close();
      try {
        await deleteDatabase(dbPath);
      } catch (_) {}
    });

    test('saveWorkout calculates total tonnage as rounds * reps_per_round * weight', () async {
      final workoutId = await DatabaseHelper.instance.saveWorkout(
        profileName: 'Test User',
        workoutName: 'ABC Strength',
        startTime: '2026-07-12T12:00:00',
        endTime: '2026-07-12T12:15:00',
        totalRoundsCompleted: 10,
        workDuration: 60,
        restDuration: 0,
        totalTimeSec: 600,
        workTimeSec: 600,
        restTimeSec: 0,
        maxHr: 160,
        avgHr: 140,
        caloriesBurntKcal: 150.0,
        notes: 'Felt strong',
        hrLogs: [],
        activityType: 'STRENGTH',
        weightMoved: 24.0,
        weightUnit: 'kg',
        repsPerRound: 6,
      );

      expect(workoutId, isNotNull);

      final logged = await db.query('workouts', where: 'id = ?', whereArgs: [workoutId]);
      expect(logged.length, equals(1));
      expect(logged.first['reps_per_round'], equals(6));
      expect(logged.first['weight_moved'], equals(24.0));
      // Tonnage: 10 rounds * 6 reps * 24.0 kg = 1440.0
      expect(logged.first['total_weight_moved'], equals(1440.0));
    });

    test('Migration from version 14 to 15 adds reps_completed and retroactively calculates reps and tonnage', () async {
      final dbPath = '${await getDatabasesPath()}/migration_v14_to_v15.db';
      await deleteDatabase(dbPath);

      // Create v14 schema
      final db = await openDatabase(
        dbPath,
        version: 14,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workouts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                total_rounds_completed INTEGER,
                weight_moved REAL DEFAULT 0.0,
                total_weight_moved REAL DEFAULT 0.0,
                reps_per_round INTEGER DEFAULT 1
            )
          ''');
        },
      );

      // Insert pre-existing v14 workout (e.g. ABC: 5 rounds, 24kg, 6 reps per round, but tonnage was only 120kg under old logic)
      await db.insert('workouts', {
        'total_rounds_completed': 5,
        'weight_moved': 24.0,
        'total_weight_moved': 120.0, // rounds * weight (5 * 24)
        'reps_per_round': 6,
      });
      await db.close();

      // Open database with version 15 to trigger the upgrade migration
      final dbV15 = await openDatabase(
        dbPath,
        version: 15,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 15) {
            await db.execute('ALTER TABLE workouts ADD COLUMN reps_completed INTEGER DEFAULT 0');
            await db.execute('UPDATE workouts SET reps_completed = total_rounds_completed * reps_per_round WHERE reps_per_round IS NOT NULL');
            await db.execute('UPDATE workouts SET total_weight_moved = total_rounds_completed * reps_per_round * weight_moved WHERE reps_per_round IS NOT NULL AND weight_moved > 0.0');
          }
        },
      );

      // Verify that reps_completed is now 30 (5 * 6) and total_weight_moved is 720.0 (5 * 6 * 24)
      final workouts = await dbV15.query('workouts');
      expect(workouts.length, equals(1));
      expect(workouts.first['reps_completed'], equals(30));
      expect(workouts.first['total_weight_moved'], equals(720.0));

      await dbV15.close();
    });

    test('saveWorkout correctly stores repsCompleted parameter for HIIT/other workouts', () async {
      final workoutId = await DatabaseHelper.instance.saveWorkout(
        profileName: 'Test User',
        workoutName: 'HIIT Session',
        startTime: '2026-07-12T13:00:00',
        endTime: '2026-07-12T13:15:00',
        totalRoundsCompleted: 10,
        workDuration: 60,
        restDuration: 10,
        totalTimeSec: 700,
        workTimeSec: 600,
        restTimeSec: 100,
        maxHr: 150,
        avgHr: 130,
        caloriesBurntKcal: 100.0,
        notes: 'HIIT notes',
        hrLogs: [],
        activityType: 'HIIT',
        repsCompleted: 120, // manually logged reps
      );

      expect(workoutId, isNotNull);

      final logged = await db.query('workouts', where: 'id = ?', whereArgs: [workoutId]);
      expect(logged.length, equals(1));
      expect(logged.first['reps_completed'], equals(120));
      expect(logged.first['total_weight_moved'], equals(0.0)); // since weightMoved = 0.0
    });

    test('Migration from version 15 to 16 updates reps_per_round from template and corrects reps and tonnage', () async {
      final dbPath = '${await getDatabasesPath()}/migration_v15_to_v16.db';
      await deleteDatabase(dbPath);

      // Create v15 schema
      final db = await openDatabase(
        dbPath,
        version: 15,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workout_templates (
                profile_name TEXT,
                template_name TEXT,
                reps_per_round INTEGER DEFAULT 1
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workouts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_name TEXT,
                workout_name TEXT,
                total_rounds_completed INTEGER,
                weight_moved REAL DEFAULT 0.0,
                total_weight_moved REAL DEFAULT 0.0,
                reps_per_round INTEGER DEFAULT 1,
                reps_completed INTEGER DEFAULT 0
            )
          ''');
        },
      );

      // Insert template with 6 reps per round
      await db.insert('workout_templates', {
        'profile_name': 'Rohit',
        'template_name': 'ABC - Double 18KG more rest',
        'reps_per_round': 6,
      });

      // Insert workout completed with reps_per_round = 1 (pre-existing v14 row defaulted to 1)
      await db.insert('workouts', {
        'profile_name': 'Rohit',
        'workout_name': 'ABC - Double 18KG more rest',
        'total_rounds_completed': 18,
        'weight_moved': 36.0,
        'total_weight_moved': 648.0, // 18 * 1 * 36.0
        'reps_per_round': 1,
        'reps_completed': 18, // 18 * 1
      });
      await db.close();

      // Open database with version 16 to trigger the upgrade migration
      final dbV16 = await openDatabase(
        dbPath,
        version: 16,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 16) {
            await db.execute('''
              UPDATE workouts 
              SET reps_per_round = (
                SELECT reps_per_round 
                FROM workout_templates 
                WHERE workout_templates.template_name = workouts.workout_name 
                  AND workout_templates.profile_name = workouts.profile_name
              )
              WHERE EXISTS (
                SELECT 1 
                FROM workout_templates 
                WHERE workout_templates.template_name = workouts.workout_name 
                  AND workout_templates.profile_name = workouts.profile_name
              )
            ''');
            await db.execute('UPDATE workouts SET reps_completed = total_rounds_completed * reps_per_round WHERE reps_per_round IS NOT NULL');
            await db.execute('UPDATE workouts SET total_weight_moved = total_rounds_completed * reps_per_round * weight_moved WHERE reps_per_round IS NOT NULL AND weight_moved > 0.0');
          }
        },
      );

      // Verify that reps_per_round is now 6, reps_completed is 108 (18 * 6) and total_weight_moved is 3888.0 (18 * 6 * 36)
      final workouts = await dbV16.query('workouts');
      expect(workouts.length, equals(1));
      expect(workouts.first['reps_per_round'], equals(6));
      expect(workouts.first['reps_completed'], equals(108));
      expect(workouts.first['total_weight_moved'], equals(3888.0));

      await dbV16.close();
    });

    test('Heart Rate Recovery (HRR) save and updateWorkoutHRR with 90s early finish', () async {
      final db = await DatabaseHelper.instance.database;

      final workoutId = await DatabaseHelper.instance.saveWorkout(
        profileName: 'Default',
        workoutName: 'HRR Test Workout',
        startTime: DateTime.now().toIso8601String(),
        endTime: DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
        totalRoundsCompleted: 10,
        workDuration: 40,
        restDuration: 20,
        totalTimeSec: 600,
        workTimeSec: 400,
        restTimeSec: 200,
        maxHr: 180,
        avgHr: 150,
        caloriesBurntKcal: 120.0,
        notes: 'Testing HRR tracking',
        hrLogs: [
          {'capture_time': DateTime.now().toIso8601String(), 'bpm': 180, 'zone': 'ZONE 5', 'is_recovery': 0},
        ],
      );

      expect(workoutId, isNotNull);

      // Simulate early recovery end at 90s (drop1 = 180 - 150 = 30 bpm, drop2 = NULL)
      await DatabaseHelper.instance.updateWorkoutHRR(
        workoutId: workoutId!,
        hrr1min: 30,
        hrr2min: null,
        recoveryDurationSec: 90,
      );

      final result = await db.query('workouts', where: 'id = ?', whereArgs: [workoutId]);
      expect(result.length, equals(1));
      expect(result.first['hrr_1min'], equals(30));
      expect(result.first['hrr_2min'], isNull);
      expect(result.first['recovery_duration_sec'], equals(90));
    });

    test('HrrService manages background recovery tracking independently of UI screens', () async {
      final db = await DatabaseHelper.instance.database;

      final workoutId = await DatabaseHelper.instance.saveWorkout(
        profileName: 'Default',
        workoutName: 'HrrService Background Test',
        startTime: DateTime.now().toIso8601String(),
        endTime: DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
        totalRoundsCompleted: 5,
        workDuration: 40,
        restDuration: 20,
        totalTimeSec: 300,
        workTimeSec: 200,
        restTimeSec: 100,
        maxHr: 175,
        avgHr: 145,
        caloriesBurntKcal: 80.0,
        notes: 'Testing HrrService background execution',
        hrLogs: [],
      );

      expect(workoutId, isNotNull);

      // Start recovery via HrrService singleton
      HrrService.instance.startRecovery(workoutId: workoutId!, peakHr: 175);

      expect(HrrService.instance.state.isTracking, isTrue);
      expect(HrrService.instance.state.workoutId, equals(workoutId));
      expect(HrrService.instance.state.peakHr, equals(175));
      expect(HrrService.instance.state.secondsRemaining, equals(120));

      // Simulate 90 seconds elapsed in background (30s remaining)
      HrrService.instance.stateNotifier.value = HrrService.instance.state.copyWith(secondsRemaining: 30);
      await HrrService.instance.finalizeRecovery();

      expect(HrrService.instance.state.isTracking, isFalse);

      final result = await db.query('workouts', where: 'id = ?', whereArgs: [workoutId]);
      expect(result.length, equals(1));
      expect(result.first['recovery_duration_sec'], equals(90));
    });

    test('Migration from version 20 to 21 adds Focus Music preferences to profiles and workout_templates', () async {
      final migDbPath = '${await getDatabasesPath()}/migration_v20_to_v21.db';
      await deleteDatabase(migDbPath);

      // Create v20 schema
      final dbV20 = await openDatabase(
        migDbPath,
        version: 20,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS profiles (
                name TEXT PRIMARY KEY,
                created_at TEXT NOT NULL
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
                activity_type TEXT DEFAULT 'HIIT'
            )
          ''');
        },
      );

      await dbV20.insert('profiles', {
        'name': 'Default',
        'created_at': DateTime.now().toIso8601String(),
      });
      await dbV20.insert('workout_templates', {
        'profile_name': 'Default',
        'template_name': 'Legacy HIIT',
        'rounds': 10,
        'work_time': 40,
        'rest_time': 20,
        'activity_type': 'HIIT',
      });
      await dbV20.close();

      // Upgrade to v21
      final dbV21 = await openDatabase(
        migDbPath,
        version: 21,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 21) {
            await db.execute('ALTER TABLE profiles ADD COLUMN music_volume REAL DEFAULT 0.7');
            await db.execute('ALTER TABLE profiles ADD COLUMN music_muted INTEGER DEFAULT 0');
            await db.execute("ALTER TABLE workout_templates ADD COLUMN music_mode TEXT DEFAULT 'AUTO'");
          }
        },
      );

      final profiles = await dbV21.query('profiles', where: 'name = ?', whereArgs: ['Default']);
      expect(profiles.isNotEmpty, isTrue);
      expect(profiles.first['music_volume'], equals(0.7));
      expect(profiles.first['music_muted'], equals(0));

      final legacyTemplates = await dbV21.query(
        'workout_templates',
        where: 'profile_name = ? AND template_name = ?',
        whereArgs: ['Default', 'Legacy HIIT'],
      );
      expect(legacyTemplates.length, equals(1));
      expect(legacyTemplates.first['music_mode'], equals('AUTO'));

      await dbV21.update(
        'profiles',
        {'music_volume': 0.55, 'music_muted': 1},
        where: 'name = ?',
        whereArgs: ['Default'],
      );
      final updatedProfiles = await dbV21.query('profiles', where: 'name = ?', whereArgs: ['Default']);
      expect(updatedProfiles.first['music_volume'], closeTo(0.55, 0.001));
      expect(updatedProfiles.first['music_muted'], equals(1));

      await dbV21.insert('workout_templates', {
        'profile_name': 'Default',
        'template_name': 'Kettlebell Complex',
        'rounds': 15,
        'work_time': 45,
        'rest_time': 15,
        'activity_type': 'STRENGTH',
        'music_mode': 'STRENGTH',
      });

      final templates = await dbV21.query(
        'workout_templates',
        where: 'profile_name = ? AND template_name = ?',
        whereArgs: ['Default', 'Kettlebell Complex'],
      );
      expect(templates.length, equals(1));
      expect(templates.first['music_mode'], equals('STRENGTH'));

      await dbV21.close();
      await deleteDatabase(migDbPath);
    });
  });
}

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('emom_timer.db');
    return _database!;
  }

  Future<File> _getConfigFile() async {
    if (Platform.isIOS || Platform.isAndroid) {
      final documentsDir = await getApplicationDocumentsDirectory();
      return File(join(documentsDir.path, '.emom_timer_config.json'));
    }
    final home = Platform.environment['HOME'] ?? '';
    return File(join(home, '.emom_timer_config.json'));
  }

  Future<String> _getBaseDir() async {
    final configFile = await _getConfigFile();
    if (await configFile.exists()) {
      try {
        final content = await configFile.readAsString();
        final Map<String, dynamic> config = jsonDecode(content);
        if (config.containsKey('base_dir')) {
          return config['base_dir'] as String;
        }
      } catch (e) {
        debugPrint('Error reading config: $e');
      }
    }
    
    final documentsDir = await getApplicationDocumentsDirectory();
    return join(documentsDir.path, 'EMOM Timer');
  }

  Future<String> getActiveProfileName() async {
    final configFile = await _getConfigFile();
    
    if (await configFile.exists()) {
      try {
        final content = await configFile.readAsString();
        final Map<String, dynamic> config = jsonDecode(content);
        if (config.containsKey('last_used_profile')) {
          return config['last_used_profile'] as String;
        }
      } catch (e) {
        debugPrint('Error reading config for profile: $e');
      }
    }
    
    // Fallback: first profile in DB
    try {
      if (_database != null) {
        final res = await _database!.query('profiles', limit: 1);
        if (res.isNotEmpty) return res.first['name'] as String;
      }
    } catch (_) {}
    return 'Default';
  }

  Future<void> setActiveProfileName(String name) async {
    final configFile = await _getConfigFile();
    Map<String, dynamic> config = {};
    if (await configFile.exists()) {
      try {
        config = jsonDecode(await configFile.readAsString());
      } catch (_) {}
    }
    config['last_used_profile'] = name;
    await configFile.writeAsString(jsonEncode(config));
  }

  Future<Database> _initDB(String fileName) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final baseDir = await _getBaseDir();
    final dbPath = join(baseDir, fileName);
    
    // Ensure the directory exists
    final dir = Directory(baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (db) async {
          try {
            await db.execute('PRAGMA journal_mode=DELETE');
          } catch (e) {
            debugPrint('DatabaseHelper: journal_mode setup note: $e');
          }
          try {
            await db.execute('PRAGMA foreign_keys=ON');
          } catch (e) {
            debugPrint('DatabaseHelper: foreign_keys setup note: $e');
          }
        },
        onCreate: _createDB,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE workout_templates ADD COLUMN continuous_mode INTEGER DEFAULT 0');
          }
          if (oldVersion < 3) {
            await db.execute('ALTER TABLE workouts ADD COLUMN workout_name TEXT');
          }
          if (oldVersion < 4) {
            await db.execute('ALTER TABLE profiles ADD COLUMN health_enabled INTEGER DEFAULT 0');
          }
        },
      ),
    );
  }

  Future _createDB(Database db, int version) async {
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

    await db.execute('CREATE INDEX IF NOT EXISTS idx_workouts_start_time ON workouts(start_time)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_workouts_profile_name ON workouts(profile_name)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS heart_rate_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          workout_id INTEGER,
          capture_time TEXT,
          bpm INTEGER,
          zone TEXT,
          FOREIGN KEY(workout_id) REFERENCES workouts(id) ON DELETE CASCADE
      )
    ''');
    
    await db.execute('CREATE INDEX IF NOT EXISTS idx_hr_logs_workout_id ON heart_rate_logs(workout_id)');
    
    // Create default profile if database is brand new, safely ignoring if it exists
    await db.execute('''
      INSERT OR IGNORE INTO profiles (name, created_at, weight_unit_pref, auto_connect_hr)
      VALUES ('Default', ?, 'kg', 1)
    ''', [DateTime.now().toIso8601String()]);
  }

  Future<List<Map<String, dynamic>>> getWorkoutsForDay(String profileName, String dateStr) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT * FROM workouts
      WHERE profile_name = ? AND DATE(start_time) = DATE(?)
      ORDER BY start_time ASC
    ''', [profileName, dateStr]);
  }

  Future<List<Map<String, dynamic>>> getHeartRateLogs(int workoutId) async {
    final db = await database;
    return await db.query(
      'heart_rate_logs',
      where: 'workout_id = ?',
      whereArgs: [workoutId],
      orderBy: 'capture_time ASC'
    );
  }

  Future<int?> saveWorkout({
    required String profileName,
    String? workoutName,
    required String startTime,
    required String endTime,
    required int totalRoundsCompleted,
    required int workDuration,
    required int restDuration,
    required int totalTimeSec,
    required int workTimeSec,
    required int restTimeSec,
    required int maxHr,
    required int avgHr,
    required double caloriesBurntKcal,
    required String notes,
    required List<Map<String, dynamic>> hrLogs,
  }) async {
    final db = await database;
    try {
      return await db.transaction((txn) async {
        final workoutId = await txn.insert('workouts', {
          'profile_name': profileName,
          'workout_name': workoutName,
          'start_time': startTime,
          'end_time': endTime,
          'total_rounds_completed': totalRoundsCompleted,
          'work_duration': workDuration,
          'rest_duration': restDuration,
          'total_time_sec': totalTimeSec,
          'work_time_sec': workTimeSec,
          'rest_time_sec': restTimeSec,
          'max_hr': maxHr,
          'avg_hr': avgHr,
          'calories_burnt_kcal': caloriesBurntKcal,
          'notes': notes,
        });

        for (var log in hrLogs) {
          await txn.insert('heart_rate_logs', {
            'workout_id': workoutId,
            'capture_time': log['capture_time'],
            'bpm': log['bpm'],
            'zone': log['zone'],
          });
        }

        debugPrint('DatabaseHelper: Workout saved with ID: $workoutId, logs: ${hrLogs.length}');
        return workoutId;
      });
    } catch (e) {
      debugPrint('DatabaseHelper: Error saving workout: $e');
      return null;
    }
  }
}

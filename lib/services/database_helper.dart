import 'dart:io';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
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

  Future<String> _getBaseDir() async {
    final home = Platform.environment['HOME'] ?? '';
    final configFile = File(join(home, '.emom_timer_config.json'));
    
    if (await configFile.exists()) {
      try {
        final content = await configFile.readAsString();
        final Map<String, dynamic> config = jsonDecode(content);
        if (config.containsKey('base_dir')) {
          return config['base_dir'] as String;
        }
      } catch (e) {
        print('Error reading config: $e');
      }
    }
    
    return join(home, 'Documents', 'EMOM Timer');
  }

  Future<String> getActiveProfileName() async {
    final home = Platform.environment['HOME'] ?? '';
    final configFile = File(join(home, '.emom_timer_config.json'));
    
    if (await configFile.exists()) {
      try {
        final content = await configFile.readAsString();
        final Map<String, dynamic> config = jsonDecode(content);
        if (config.containsKey('last_used_profile')) {
          return config['last_used_profile'] as String;
        }
      } catch (e) {
        print('Error reading config for profile: \$e');
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
    final home = Platform.environment['HOME'] ?? '';
    final configFile = File(join(home, '.emom_timer_config.json'));
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
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA foreign_keys=ON');
        },
        onCreate: _createDB,
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
          FOREIGN KEY(profile_name) REFERENCES profiles(name) ON DELETE CASCADE,
          UNIQUE(profile_name, template_name)
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
}

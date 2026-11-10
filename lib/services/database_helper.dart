import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  @visibleForTesting
  static String? activeProfileOverride;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('emom_timer.db');
    return _database!;
  }

  @visibleForTesting
  void setDatabaseForTesting(Database db) {
    _database = db;
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
    if (activeProfileOverride != null) return activeProfileOverride!;
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
    if (activeProfileOverride != null) {
      activeProfileOverride = name;
      return;
    }
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
        version: 21,
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
          if (oldVersion < 5) {
            try {
              await db.execute("ALTER TABLE workout_templates ADD COLUMN activity_type TEXT DEFAULT 'HIIT'");
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for workout_templates activity_type: $e');
            }
            try {
              await db.execute("ALTER TABLE workouts ADD COLUMN activity_type TEXT DEFAULT 'HIIT'");
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for workouts activity_type: $e');
            }
          }
          if (oldVersion < 6) {
            try {
              await db.execute('ALTER TABLE profiles ADD COLUMN save_history INTEGER DEFAULT 1');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for profiles save_history: $e');
            }
          }
          if (oldVersion < 7) {
            try {
              await db.execute('ALTER TABLE workout_templates ADD COLUMN auto_regulate INTEGER DEFAULT 1');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for workout_templates auto_regulate: $e');
            }
          }
          if (oldVersion < 8) {
            try {
              await db.execute('ALTER TABLE profiles ADD COLUMN treadmill_enabled INTEGER DEFAULT 0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for profiles treadmill_enabled: $e');
            }
            try {
              await db.execute('ALTER TABLE profiles ADD COLUMN treadmill_preset_1 REAL DEFAULT 2.0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for profiles treadmill_preset_1: $e');
            }
            try {
              await db.execute('ALTER TABLE profiles ADD COLUMN treadmill_preset_2 REAL DEFAULT 4.0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for profiles treadmill_preset_2: $e');
            }
            try {
              await db.execute('ALTER TABLE profiles ADD COLUMN treadmill_preset_3 REAL DEFAULT 6.0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for profiles treadmill_preset_3: $e');
            }
          }
          if (oldVersion < 9) {
            try {
              await db.execute('ALTER TABLE workout_templates ADD COLUMN treadmill_workout INTEGER DEFAULT 0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for workout_templates treadmill_workout: $e');
            }
            try {
              await db.execute('ALTER TABLE workout_templates ADD COLUMN work_speed REAL DEFAULT 4.0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for workout_templates work_speed: $e');
            }
            try {
              await db.execute('ALTER TABLE workout_templates ADD COLUMN rest_speed REAL DEFAULT 0.0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for workout_templates rest_speed: $e');
            }
          }
          if (oldVersion < 10) {
            try {
              await db.execute('ALTER TABLE workouts ADD COLUMN run_distance REAL DEFAULT 0.0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for workouts run_distance: $e');
            }
            try {
              await db.execute('ALTER TABLE workouts ADD COLUMN run_peak_speed REAL DEFAULT 0.0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for workouts run_peak_speed: $e');
            }
            try {
              await db.execute('ALTER TABLE workouts ADD COLUMN run_avg_speed REAL DEFAULT 0.0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for workouts run_avg_speed: $e');
            }
          }
          if (oldVersion < 11) {
            try {
              await db.execute("ALTER TABLE profiles ADD COLUMN distance_unit_pref TEXT DEFAULT 'km'");
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for profiles distance_unit_pref: $e');
            }
          }
          if (oldVersion < 12) {
            try {
              await db.execute("ALTER TABLE profiles ADD COLUMN updated_at TEXT");
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for profiles updated_at: $e');
            }
          }
          if (oldVersion < 13) {
            try {
              await db.execute('ALTER TABLE workout_templates ADD COLUMN weight_moved REAL DEFAULT 0.0');
              await db.execute("ALTER TABLE workout_templates ADD COLUMN weight_unit TEXT DEFAULT 'kg'");
              await db.execute('ALTER TABLE workout_templates ADD COLUMN ruck_weight REAL DEFAULT 0.0');
              await db.execute("ALTER TABLE workout_templates ADD COLUMN ruck_weight_unit TEXT DEFAULT 'lbs'");
              
              await db.execute('ALTER TABLE workouts ADD COLUMN weight_moved REAL DEFAULT 0.0');
              await db.execute("ALTER TABLE workouts ADD COLUMN weight_unit TEXT DEFAULT 'kg'");
              await db.execute('ALTER TABLE workouts ADD COLUMN total_weight_moved REAL DEFAULT 0.0');
              await db.execute('ALTER TABLE workouts ADD COLUMN ruck_weight REAL DEFAULT 0.0');
              await db.execute("ALTER TABLE workouts ADD COLUMN ruck_weight_unit TEXT DEFAULT 'lbs'");
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for version 13: $e');
            }
          }
          if (oldVersion < 14) {
            try {
              await db.execute('ALTER TABLE workout_templates ADD COLUMN reps_per_round INTEGER DEFAULT 1');
              await db.execute('ALTER TABLE workouts ADD COLUMN reps_per_round INTEGER DEFAULT 1');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for version 14: $e');
            }
          }
          if (oldVersion < 15) {
            try {
              await db.execute('ALTER TABLE workouts ADD COLUMN reps_completed INTEGER DEFAULT 0');
              await db.execute('UPDATE workouts SET reps_completed = total_rounds_completed * reps_per_round WHERE reps_per_round IS NOT NULL');
              await db.execute('UPDATE workouts SET total_weight_moved = total_rounds_completed * reps_per_round * weight_moved WHERE reps_per_round IS NOT NULL AND weight_moved > 0.0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for version 15: $e');
            }
          }
          if (oldVersion < 16) {
            try {
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
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for version 16: $e');
            }
          }
          if (oldVersion < 17) {
            try {
              await db.execute('''
                UPDATE workouts 
                SET reps_per_round = (
                  SELECT reps_per_round 
                  FROM workout_templates 
                  WHERE workout_templates.profile_name = workouts.profile_name
                    AND (
                      workout_templates.template_name = workouts.workout_name 
                      OR workout_templates.template_name = REPLACE(workouts.workout_name, ' (Modified)', '')
                    )
                  LIMIT 1
                )
                WHERE EXISTS (
                  SELECT 1 
                  FROM workout_templates 
                  WHERE workout_templates.profile_name = workouts.profile_name
                    AND (
                      workout_templates.template_name = workouts.workout_name 
                      OR workout_templates.template_name = REPLACE(workouts.workout_name, ' (Modified)', '')
                    )
                )
              ''');
              await db.execute('UPDATE workouts SET reps_completed = total_rounds_completed * reps_per_round WHERE reps_per_round IS NOT NULL AND (reps_completed IS NULL OR reps_completed = 0 OR reps_completed = total_rounds_completed)');
              await db.execute('UPDATE workouts SET total_weight_moved = total_rounds_completed * reps_per_round * weight_moved WHERE reps_per_round IS NOT NULL AND weight_moved > 0.0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for version 17: $e');
            }
          }
          if (oldVersion < 18) {
            try {
              await db.execute('''
                UPDATE workouts 
                SET reps_per_round = (
                  SELECT reps_per_round 
                  FROM workout_templates 
                  WHERE workout_templates.profile_name = workouts.profile_name
                    AND (
                      workout_templates.template_name = workouts.workout_name 
                      OR workout_templates.template_name = REPLACE(workouts.workout_name, ' (Modified)', '')
                    )
                  LIMIT 1
                )
                WHERE EXISTS (
                  SELECT 1 
                  FROM workout_templates 
                  WHERE workout_templates.profile_name = workouts.profile_name
                    AND (
                      workout_templates.template_name = workouts.workout_name 
                      OR workout_templates.template_name = REPLACE(workouts.workout_name, ' (Modified)', '')
                    )
                )
              ''');
              await db.execute('UPDATE workouts SET reps_completed = total_rounds_completed * reps_per_round WHERE reps_per_round IS NOT NULL AND (reps_completed IS NULL OR reps_completed = 0 OR reps_completed = total_rounds_completed)');
              await db.execute('UPDATE workouts SET total_weight_moved = total_rounds_completed * reps_per_round * weight_moved WHERE reps_per_round IS NOT NULL AND weight_moved > 0.0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for version 18: $e');
            }
          }
          if (oldVersion < 19) {
            try {
              await db.execute('ALTER TABLE workouts ADD COLUMN hrr_1min INTEGER');
              await db.execute('ALTER TABLE workouts ADD COLUMN hrr_2min INTEGER');
              await db.execute('ALTER TABLE workouts ADD COLUMN recovery_duration_sec INTEGER');
              await db.execute('ALTER TABLE heart_rate_logs ADD COLUMN is_recovery INTEGER DEFAULT 0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for version 19: $e');
            }
          }
          if (oldVersion < 20) {
            try {
              await db.execute("ALTER TABLE profiles ADD COLUMN theme_mode TEXT DEFAULT 'dark'");
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for version 20: $e');
            }
          }
          if (oldVersion < 21) {
            try {
              await db.execute('ALTER TABLE profiles ADD COLUMN music_volume REAL DEFAULT 0.7');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for version 21 music_volume: $e');
            }
            try {
              await db.execute('ALTER TABLE profiles ADD COLUMN music_muted INTEGER DEFAULT 0');
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for version 21 music_muted: $e');
            }
            try {
              await db.execute("ALTER TABLE workout_templates ADD COLUMN music_mode TEXT DEFAULT 'AUTO'");
            } catch (e) {
              debugPrint('DatabaseHelper: migration warning for version 21 music_mode: $e');
            }
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
          distance_unit_pref TEXT DEFAULT 'km',
          auto_connect_hr INTEGER,
          health_enabled INTEGER DEFAULT 0,
          save_history INTEGER DEFAULT 1,
          treadmill_enabled INTEGER DEFAULT 0,
          treadmill_preset_1 REAL DEFAULT 2.0,
          treadmill_preset_2 REAL DEFAULT 4.0,
          treadmill_preset_3 REAL DEFAULT 6.0,
          theme_mode TEXT DEFAULT 'dark',
          music_volume REAL DEFAULT 0.7,
          music_muted INTEGER DEFAULT 0,
          updated_at TEXT
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
          activity_type TEXT DEFAULT 'HIIT',
          auto_regulate INTEGER DEFAULT 1,
          treadmill_workout INTEGER DEFAULT 0,
          work_speed REAL DEFAULT 4.0,
          rest_speed REAL DEFAULT 0.0,
          weight_moved REAL DEFAULT 0.0,
          weight_unit TEXT DEFAULT 'kg',
          ruck_weight REAL DEFAULT 0.0,
          ruck_weight_unit TEXT DEFAULT 'lbs',
          reps_per_round INTEGER DEFAULT 1,
          music_mode TEXT DEFAULT 'AUTO',
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

    await db.execute('CREATE INDEX IF NOT EXISTS idx_workouts_start_time ON workouts(start_time)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_workouts_profile_name ON workouts(profile_name)');

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
    
    await db.execute('CREATE INDEX IF NOT EXISTS idx_hr_logs_workout_id ON heart_rate_logs(workout_id)');
    
    // Create default profile if database is brand new, safely ignoring if it exists
    final nowStr = DateTime.now().toIso8601String();
    await db.execute('''
      INSERT OR IGNORE INTO profiles (name, created_at, weight_unit_pref, auto_connect_hr, updated_at)
      VALUES ('Default', ?, 'kg', 1, ?)
    ''', [nowStr, nowStr]);
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
    String activityType = 'HIIT',
    double runDistance = 0.0,
    double runPeakSpeed = 0.0,
    double runAvgSpeed = 0.0,
    double weightMoved = 0.0,
    String weightUnit = 'kg',
    double ruckWeight = 0.0,
    String ruckWeightUnit = 'lbs',
    int repsPerRound = 1,
    int repsCompleted = 0,
    int? hrr1min,
    int? hrr2min,
    int? recoveryDurationSec,
  }) async {
    final db = await database;
    try {
      return await db.transaction((txn) async {
        final int calculatedReps = repsCompleted > 0
            ? repsCompleted
            : (totalRoundsCompleted * repsPerRound);
        final double totalWeightMoved = calculatedReps * weightMoved;
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
          'activity_type': activityType,
          'run_distance': runDistance,
          'run_peak_speed': runPeakSpeed,
          'run_avg_speed': runAvgSpeed,
          'weight_moved': weightMoved,
          'weight_unit': weightUnit,
          'total_weight_moved': totalWeightMoved,
          'ruck_weight': ruckWeight,
          'ruck_weight_unit': ruckWeightUnit,
          'reps_per_round': repsPerRound,
          'reps_completed': calculatedReps,
          'hrr_1min': hrr1min,
          'hrr_2min': hrr2min,
          'recovery_duration_sec': recoveryDurationSec,
        });

        for (var log in hrLogs) {
          await txn.insert('heart_rate_logs', {
            'workout_id': workoutId,
            'capture_time': log['capture_time'],
            'bpm': log['bpm'],
            'zone': log['zone'],
            'is_recovery': log['is_recovery'] ?? 0,
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

  Future<void> updateWorkoutHRR({
    required int workoutId,
    int? hrr1min,
    int? hrr2min,
    required int recoveryDurationSec,
  }) async {
    try {
      final db = await database;
      await db.update(
        'workouts',
        {
          'hrr_1min': hrr1min,
          'hrr_2min': hrr2min,
          'recovery_duration_sec': recoveryDurationSec,
        },
        where: 'id = ?',
        whereArgs: [workoutId],
      );
      debugPrint('DatabaseHelper: Updated workout $workoutId HRR: 1m=$hrr1min, 2m=$hrr2min, dur=${recoveryDurationSec}s');
    } catch (e) {
      debugPrint('DatabaseHelper: Error updating workout HRR: $e');
    }
  }

  Future<void> insertHeartRateLog({
    required int workoutId,
    required String captureTime,
    required int bpm,
    required String zone,
    int isRecovery = 0,
  }) async {
    try {
      final db = await database;
      await db.insert('heart_rate_logs', {
        'workout_id': workoutId,
        'capture_time': captureTime,
        'bpm': bpm,
        'zone': zone,
        'is_recovery': isRecovery,
      });
    } catch (e) {
      debugPrint('DatabaseHelper: Error inserting HR log: $e');
    }
  }
}

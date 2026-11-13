import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';
import 'package:emom_timer_flutter/main.dart';
import 'package:emom_timer_flutter/screens/details_screen.dart';
import 'package:emom_timer_flutter/screens/history_screen.dart';
import 'package:emom_timer_flutter/screens/library_screen.dart';
import 'package:emom_timer_flutter/screens/profile_screen.dart';
import 'package:emom_timer_flutter/screens/timer_screen.dart';
import 'package:emom_timer_flutter/services/audio_service.dart';
import 'package:emom_timer_flutter/services/bluetooth_service.dart';
import 'package:emom_timer_flutter/services/database_helper.dart';
import 'package:emom_timer_flutter/theme/app_theme.dart';

class _FakeWakelockPlatform extends WakelockPlusPlatformInterface with MockPlatformInterfaceMixin {
  @override
  bool get isMock => true;

  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

class _FakeAudioPlatform extends AudioplayersPlatformInterface with MockPlatformInterfaceMixin {
  final Map<String, StreamController<AudioEvent>> _controllers = {};

  StreamController<AudioEvent> _ctrl(String playerId) =>
      _controllers.putIfAbsent(playerId, () => StreamController<AudioEvent>.broadcast());

  @override
  Future<void> create(String playerId) async {
    _ctrl(playerId);
  }

  @override
  Future<void> dispose(String playerId) async {
    await _controllers.remove(playerId)?.close();
  }

  @override
  Future<void> pause(String playerId) async {}

  @override
  Future<void> stop(String playerId) async {}

  @override
  Future<void> resume(String playerId) async {}

  @override
  Future<void> release(String playerId) async {}

  @override
  Future<void> seek(String playerId, Duration position) async {
    _ctrl(playerId).add(const AudioEvent(eventType: AudioEventType.seekComplete));
  }

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setVolume(String playerId, double volume) async {}

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}

  @override
  Future<void> setSourceUrl(String playerId, String url, {bool? isLocal, String? mimeType}) async {
    _ctrl(playerId).add(const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true));
  }

  @override
  Future<void> setSourceBytes(String playerId, Uint8List bytes, {String? mimeType}) async {
    _ctrl(playerId).add(const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true));
  }

  @override
  Future<void> setAudioContext(String playerId, AudioContext audioContext) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}

  @override
  Future<int?> getDuration(String playerId) async => 0;

  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;

  @override
  Future<void> emitLog(String playerId, String message) async {}

  @override
  Future<void> emitError(String playerId, String code, String message) async {}

  @override
  Stream<AudioEvent> getEventStream(String playerId) => _ctrl(playerId).stream;
}

Future<void> _loadFontFamily(String family, String fontDir) async {
  final loader = FontLoader(family)
    ..addFont(File('$fontDir/Roboto-Thin.ttf').readAsBytes().then((b) => ByteData.sublistView(b)))
    ..addFont(File('$fontDir/Roboto-Light.ttf').readAsBytes().then((b) => ByteData.sublistView(b)))
    ..addFont(File('$fontDir/Roboto-Regular.ttf').readAsBytes().then((b) => ByteData.sublistView(b)))
    ..addFont(File('$fontDir/Roboto-Medium.ttf').readAsBytes().then((b) => ByteData.sublistView(b)))
    ..addFont(File('$fontDir/Roboto-Bold.ttf').readAsBytes().then((b) => ByteData.sublistView(b)))
    ..addFont(File('$fontDir/Roboto-Black.ttf').readAsBytes().then((b) => ByteData.sublistView(b)));
  await loader.load();
}

Future<void> _loadFonts() async {
  const fontDir = '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts';

  for (final family in [
    'Roboto',
    'FlutterTest',
    'Ahem',
    '.AppleSystemUIFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await _loadFontFamily(family, fontDir);
  }

  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(File('$fontDir/MaterialIcons-Regular.otf').readAsBytes().then((b) => ByteData.sublistView(b)));
  await materialIcons.load();
}

void _setupMockChannels() {
  WakelockPlusPlatformInterface.instance = _FakeWakelockPlatform();
  AudioplayersPlatformInterface.instance = _FakeAudioPlatform();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final name in [
    'xyz.luan/audioplayers.global',
    'flutter_blue_plus/methods',
    'plugins.flutter.io/path_provider',
    'plugins.flutter.io/path_provider_macos',
    'plugins.flutter.io/path_provider_foundation',
    'com.chronoPulse.active/watch_hr',
    'plugins.flutter.io/shared_preferences',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'getTemporaryDirectory' ||
          call.method == 'getApplicationSupportDirectory' ||
          call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getLibraryDirectory') {
        return Directory.systemTemp.path;
      }
      if (call.method == 'getDirectoryPath') {
        return Directory.systemTemp.path;
      }
      if (call.method == 'isSupported') return false;
      return null;
    });
  }

  messenger.setMockStreamHandler(
    const EventChannel('xyz.luan/audioplayers.global/events'),
    MockStreamHandler.inline(onListen: (_, __) {}),
  );

  messenger.setMockDecodedMessageHandler<Object?>(
    const BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.path_provider_foundation.PathProviderApi.getDirectoryPath',
      StandardMessageCodec(),
    ),
    (message) async => <Object?>[Directory.systemTemp.path],
  );
}

Future<Database> _createSeededDb() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 21,
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
      },
    ),
  );

  final now = DateTime.now();
  await db.insert('profiles', {
    'name': 'Alex',
    'created_at': now.toIso8601String(),
    'max_hr': 186,
    'max_prework_hr': 142,
    'sex': 'Male',
    'birth_date': '1991-04-18',
    'weight_kg': 76.0,
    'weight_unit_pref': 'kg',
    'distance_unit_pref': 'km',
    'auto_connect_hr': 0,
    'health_enabled': 1,
    'save_history': 1,
    'treadmill_enabled': 1,
    'treadmill_preset_1': 2.5,
    'treadmill_preset_2': 5.0,
    'treadmill_preset_3': 7.5,
    'theme_mode': 'dark',
    'music_volume': 0.72,
    'music_muted': 0,
    'updated_at': now.toIso8601String(),
  });

  // Templates
  final templates = [
    {
      'profile_name': 'Alex',
      'template_name': 'Kettlebell Armor Building',
      'rounds': 6,
      'work_time': 30,
      'rest_time': 30,
      'notes': '2 Cleans • 1 Press • 3 Front Squats • Brace core on transitions',
      'continuous_mode': 0,
      'activity_type': 'STRENGTH',
      'auto_regulate': 1,
      'treadmill_workout': 0,
      'weight_moved': 24.0,
      'weight_unit': 'kg',
      'reps_per_round': 6,
      'music_mode': 'AUTO',
    },
    {
      'profile_name': 'Alex',
      'template_name': 'Pull-Ups & Ring Dips EMOM',
      'rounds': 5,
      'work_time': 25,
      'rest_time': 35,
      'notes': 'Control the eccentric tempo • Full range of motion',
      'continuous_mode': 0,
      'activity_type': 'CALISTHENICS',
      'auto_regulate': 1,
      'treadmill_workout': 0,
      'weight_moved': 0.0,
      'weight_unit': 'kg',
      'reps_per_round': 8,
      'music_mode': 'AUTO',
    },
    {
      'profile_name': 'Alex',
      'template_name': 'WalkingPad Tempo Intervals',
      'rounds': 8,
      'work_time': 90,
      'rest_time': 30,
      'notes': 'Tall posture • Quick cadence during work intervals',
      'continuous_mode': 0,
      'activity_type': 'CARDIO',
      'auto_regulate': 0,
      'treadmill_workout': 1,
      'work_speed': 6.4,
      'rest_speed': 3.2,
      'music_mode': 'AUTO',
    },
    {
      'profile_name': 'Alex',
      'template_name': 'Assault Conditioning',
      'rounds': 10,
      'work_time': 40,
      'rest_time': 20,
      'notes': 'Steady RPM output • Nasal recovery on rest',
      'continuous_mode': 0,
      'activity_type': 'HIIT',
      'auto_regulate': 1,
      'treadmill_workout': 0,
      'music_mode': 'FOCUS',
    },
    {
      'profile_name': 'Alex',
      'template_name': 'Chakra Mobility & Breathwork',
      'rounds': 6,
      'work_time': 60,
      'rest_time': 15,
      'notes': 'Slow 4-7-8 breath cycle • Hip & thoracic openers',
      'continuous_mode': 0,
      'activity_type': 'YOGA',
      'auto_regulate': 0,
      'treadmill_workout': 0,
      'music_mode': 'MEDITATION',
    },
  ];
  for (final t in templates) {
    await db.insert('workout_templates', t);
  }

  // 7-day history + Today workouts
  final today = DateTime(now.year, now.month, now.day, 8, 15);
  final historySeeds = [
    {'daysAgo': 6, 'name': 'Tabata Sprint Intervals', 'type': 'HIIT', 'rounds': 8, 'work': 160, 'rest': 80, 'maxHr': 174, 'avgHr': 148, 'cals': 185.0, 'hrr1': 29, 'hrr2': 44, 'weight': 0.0, 'reps': 0, 'dist': 0.0},
    {'daysAgo': 5, 'name': 'Kettlebell Armor Building', 'type': 'STRENGTH', 'rounds': 10, 'work': 300, 'rest': 300, 'maxHr': 162, 'avgHr': 138, 'cals': 242.0, 'hrr1': 27, 'hrr2': 42, 'weight': 24.0, 'reps': 60, 'dist': 0.0},
    {'daysAgo': 4, 'name': 'WalkingPad Tempo Intervals', 'type': 'CARDIO', 'rounds': 8, 'work': 720, 'rest': 240, 'maxHr': 156, 'avgHr': 139, 'cals': 268.0, 'hrr1': 30, 'hrr2': 47, 'weight': 0.0, 'reps': 0, 'dist': 2.18},
    {'daysAgo': 2, 'name': 'Pull-Ups & Ring Dips EMOM', 'type': 'CALISTHENICS', 'rounds': 8, 'work': 240, 'rest': 240, 'maxHr': 151, 'avgHr': 129, 'cals': 176.0, 'hrr1': 28, 'hrr2': 45, 'weight': 0.0, 'reps': 64, 'dist': 0.0},
    {'daysAgo': 1, 'name': 'Assault Conditioning', 'type': 'HIIT', 'rounds': 12, 'work': 480, 'rest': 240, 'maxHr': 178, 'avgHr': 154, 'cals': 312.0, 'hrr1': 33, 'hrr2': 51, 'weight': 0.0, 'reps': 0, 'dist': 0.0},
  ];

  for (final s in historySeeds) {
    final start = today.subtract(Duration(days: s['daysAgo'] as int));
    final totalSec = (s['work'] as int) + (s['rest'] as int);
    final end = start.add(Duration(seconds: totalSec));
    await db.insert('workouts', {
      'profile_name': 'Alex',
      'workout_name': s['name'],
      'start_time': start.toIso8601String().substring(0, 19),
      'end_time': end.toIso8601String().substring(0, 19),
      'total_rounds_completed': s['rounds'],
      'work_duration': 30,
      'rest_duration': 30,
      'total_time_sec': totalSec,
      'work_time_sec': s['work'],
      'rest_time_sec': s['rest'],
      'max_hr': s['maxHr'],
      'avg_hr': s['avgHr'],
      'calories_burnt_kcal': s['cals'],
      'notes': 'Strong pace throughout all intervals',
      'activity_type': s['type'],
      'run_distance': s['dist'],
      'run_peak_speed': (s['dist'] as double) > 0 ? 7.4 : 0.0,
      'run_avg_speed': (s['dist'] as double) > 0 ? 5.9 : 0.0,
      'weight_moved': s['weight'],
      'weight_unit': 'kg',
      'total_weight_moved': (s['weight'] as double) * (s['reps'] as int),
      'reps_per_round': (s['reps'] as int) > 0 ? ((s['reps'] as int) ~/ (s['rounds'] as int)) : 1,
      'reps_completed': s['reps'],
      'hrr_1min': s['hrr1'],
      'hrr_2min': s['hrr2'],
      'recovery_duration_sec': 120,
    });
  }

  // Today's workouts (2 sessions for Details view + curve)
  final w1Start = today;
  final w1Id = await db.insert('workouts', {
    'profile_name': 'Alex',
    'workout_name': 'Kettlebell Armor Building',
    'start_time': w1Start.toIso8601String().substring(0, 19),
    'end_time': w1Start.add(const Duration(minutes: 10)).toIso8601String().substring(0, 19),
    'total_rounds_completed': 10,
    'work_duration': 30,
    'rest_duration': 30,
    'total_time_sec': 600,
    'work_time_sec': 300,
    'rest_time_sec': 300,
    'max_hr': 168,
    'avg_hr': 142,
    'calories_burnt_kcal': 248.0,
    'notes': '2x24kg complexes crisp through round 10',
    'activity_type': 'STRENGTH',
    'weight_moved': 24.0,
    'weight_unit': 'kg',
    'total_weight_moved': 1440.0,
    'reps_per_round': 6,
    'reps_completed': 60,
    'hrr_1min': 31,
    'hrr_2min': 48,
    'recovery_duration_sec': 120,
  });

  // Insert 1Hz/10s-step HR logs for workout 1 + 120s cyan recovery tail
  for (int sec = 0; sec <= 600; sec += 10) {
    final wave = ((sec % 60) < 30) ? (sec % 30) * 0.6 : (30 - (sec % 30)) * 0.4;
    final bpm = (118 + (sec / 600.0) * 34 + wave).round().clamp(105, 168);
    final zone = bpm >= 167
        ? 'ZONE 5'
        : (bpm >= 149 ? 'ZONE 4' : (bpm >= 130 ? 'ZONE 3' : (bpm >= 112 ? 'ZONE 2' : 'ZONE 1')));
    await db.insert('heart_rate_logs', {
      'workout_id': w1Id,
      'capture_time': w1Start.add(Duration(seconds: sec)).toIso8601String().substring(0, 19),
      'bpm': bpm,
      'zone': zone,
      'is_recovery': 0,
    });
  }
  for (int sec = 10; sec <= 120; sec += 10) {
    final bpm = (168 - (sec * 0.42)).round().clamp(112, 168);
    await db.insert('heart_rate_logs', {
      'workout_id': w1Id,
      'capture_time': w1Start.add(Duration(seconds: 600 + sec)).toIso8601String().substring(0, 19),
      'bpm': bpm,
      'zone': bpm >= 130 ? 'ZONE 3' : 'ZONE 2',
      'is_recovery': 1,
    });
  }

  final w2Start = today.add(const Duration(minutes: 14));
  final w2Id = await db.insert('workouts', {
    'profile_name': 'Alex',
    'workout_name': 'WalkingPad Tempo Intervals',
    'start_time': w2Start.toIso8601String().substring(0, 19),
    'end_time': w2Start.add(const Duration(minutes: 12)).toIso8601String().substring(0, 19),
    'total_rounds_completed': 6,
    'work_duration': 90,
    'rest_duration': 30,
    'total_time_sec': 720,
    'work_time_sec': 540,
    'rest_time_sec': 180,
    'max_hr': 156,
    'avg_hr': 136,
    'calories_burnt_kcal': 215.0,
    'notes': 'Zone 2-3 aerobic steady block',
    'activity_type': 'CARDIO',
    'run_distance': 1.48,
    'run_peak_speed': 6.4,
    'run_avg_speed': 5.6,
    'hrr_1min': 29,
    'hrr_2min': 45,
    'recovery_duration_sec': 120,
  });

  for (int sec = 0; sec <= 720; sec += 15) {
    final bpm = (122 + (sec / 720.0) * 26 + ((sec % 120) < 90 ? 6 : -4)).round().clamp(112, 156);
    await db.insert('heart_rate_logs', {
      'workout_id': w2Id,
      'capture_time': w2Start.add(Duration(seconds: sec)).toIso8601String().substring(0, 19),
      'bpm': bpm,
      'zone': bpm >= 149 ? 'ZONE 4' : (bpm >= 130 ? 'ZONE 3' : 'ZONE 2'),
      'is_recovery': 0,
    });
  }

  return db;
}

Future<void> _settleDb(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  for (int i = 0; i < 10; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 60));
    if (i >= 3 && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
}

int _realisticWorkoutBpm(int sec) {
  if (sec < 10) return 96 + (sec * 1.4).round();
  if (sec < 40) return 110 + ((sec - 10) * 1.65).round() + ((sec % 3) - 1);
  if (sec < 70) return (160 - ((sec - 40) * 0.95)).round().clamp(131, 162);
  return 132 + ((sec - 70) * 2.1).round() + ((sec % 3) - 1);
}

Future<void> _captureToFile(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String outPath,
) async {
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() async => await boundary.toImage(pixelRatio: 2.0));
  final byteData = await tester.runAsync(() async => await image!.toByteData(format: ui.ImageByteFormat.png));
  final bytes = byteData!.buffer.asUint8List();
  await tester.runAsync(() async {
    await File(outPath).writeAsBytes(bytes, flush: true);
  });
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('Generate macOS and iPhone screenshots', (tester) async {
    await tester.runAsync(() async {
      await _loadFonts();
      final db = await _createSeededDb();
      DatabaseHelper.activeProfileOverride = 'Alex';
      DatabaseHelper.instance.setDatabaseForTesting(db);
    });
    _setupMockChannels();

    final screenshotTheme = AppTheme.darkTheme.copyWith(
      textTheme: AppTheme.darkTheme.textTheme.apply(fontFamily: 'Roboto'),
      primaryTextTheme: AppTheme.darkTheme.primaryTextTheme.apply(fontFamily: 'Roboto'),
      appBarTheme: AppTheme.darkTheme.appBarTheme.copyWith(
        titleTextStyle: AppTheme.darkTheme.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
      ),
    );

    final now = DateTime.now();
    final todayDateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final boundaryKey = GlobalKey();

    // =========================================================================
    // PHASE 1: CLEAN DETAILS + IDLE + HISTORY + LIBRARY + PROFILE (No active HRR/SnackBar)
    // =========================================================================

    // 1A. macOS Details Screen (1280 x 800 logical -> 2560 x 1600 Retina)
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: screenshotTheme,
          home: DetailsScreen(dateStr: todayDateStr, profileName: 'Alex'),
        ),
      ),
    );
    await _settleDb(tester);
    await _captureToFile(tester, boundaryKey, 'screenshots/macOS_Details.png');

    // 1B. macOS MainNavigationScreen (History, Profile, Library, Main, Active)
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: screenshotTheme,
          home: const MainNavigationScreen(),
        ),
      ),
    );
    await _settleDb(tester);

    await tester.tap(find.text('History'));
    await _settleDb(tester);
    await _captureToFile(tester, boundaryKey, 'screenshots/macOS_History.png');

    await tester.tap(find.text('Profile'));
    await _settleDb(tester);
    await _captureToFile(tester, boundaryKey, 'screenshots/macOS_Profile.png');

    await tester.tap(find.text('Library'));
    await _settleDb(tester);
    await _captureToFile(tester, boundaryKey, 'screenshots/macOS_Library.png');

    // Load 'Kettlebell Armor Building' onto Timer tab -> captures Main & Active
    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('Kettlebell Armor Building'), matching: find.byType(Card)),
        matching: find.widgetWithText(ElevatedButton, 'Start'),
      ),
    );
    await _settleDb(tester);
    AppBluetoothService.instance.simulateHeartRateForTesting(74, connected: true);
    await tester.pump(const Duration(milliseconds: 120));
    await _captureToFile(tester, boundaryKey, 'screenshots/macOS_Main.png');

    await tester.tap(
      find.descendant(
        of: find.byType(TimerScreen),
        matching: find.text('Start Workout'),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 82; i++) {
      AppBluetoothService.instance.simulateHeartRateForTesting(_realisticWorkoutBpm(i), connected: true);
      await tester.pump(const Duration(seconds: 1));
    }
    await _captureToFile(tester, boundaryKey, 'screenshots/macOS_Active.png');

    // Stop music and unmount cleanly without saving/triggering SnackBar or HRR
    await tester.runAsync(() => AudioService.instance.stopMusic(fadeDuration: Duration.zero));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // 2A. iPhone Details Screen (402 x 874 logical -> 804 x 1748 Retina)
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: screenshotTheme,
          home: DetailsScreen(dateStr: todayDateStr, profileName: 'Alex'),
        ),
      ),
    );
    await _settleDb(tester);
    await _captureToFile(tester, boundaryKey, 'screenshots/iPhone_Details.png');

    // 2B. iPhone MainNavigationScreen (History, Profile, Library, Timer, Workout)
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: screenshotTheme,
          home: const MainNavigationScreen(),
        ),
      ),
    );
    await _settleDb(tester);

    await tester.tap(find.text('History'));
    await _settleDb(tester);
    await _captureToFile(tester, boundaryKey, 'screenshots/iPhone_History.png');

    await tester.tap(find.text('Profile'));
    await _settleDb(tester);
    await _captureToFile(tester, boundaryKey, 'screenshots/iPhone_Profile.png');

    await tester.tap(find.text('Library'));
    await _settleDb(tester);
    await _captureToFile(tester, boundaryKey, 'screenshots/iPhone_Library.png');

    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('Kettlebell Armor Building'), matching: find.byType(Card)),
        matching: find.widgetWithText(ElevatedButton, 'Start'),
      ),
    );
    await _settleDb(tester);
    AppBluetoothService.instance.simulateHeartRateForTesting(76, connected: true);
    await tester.pump(const Duration(milliseconds: 120));
    await _captureToFile(tester, boundaryKey, 'screenshots/iPhone_Timer.png');

    await tester.tap(
      find.descendant(
        of: find.byType(TimerScreen),
        matching: find.text('Start'),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 82; i++) {
      AppBluetoothService.instance.simulateHeartRateForTesting(_realisticWorkoutBpm(i), connected: true);
      await tester.pump(const Duration(seconds: 1));
    }
    await _captureToFile(tester, boundaryKey, 'screenshots/iPhone_Workout.png');

    // Stop music & unmount cleanly
    await tester.runAsync(() => AudioService.instance.stopMusic(fadeDuration: Duration.zero));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

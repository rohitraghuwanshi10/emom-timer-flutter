import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:emom_timer_flutter/screens/library_screen.dart';
import 'package:emom_timer_flutter/services/database_helper.dart';

void main() {
  // Initialize sqflite FFI for testing database operations
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Workout Library Widget & Logic Tests', () {
    late Database db;
    late String activeProfile;

    setUp(() async {
      final dbPath = inMemoryDatabasePath;
      db = await openDatabase(
        dbPath,
        version: 6,
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
                health_enabled INTEGER DEFAULT 0,
                save_history INTEGER DEFAULT 1
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
                FOREIGN KEY(profile_name) REFERENCES profiles(name) ON DELETE CASCADE,
                UNIQUE(profile_name, template_name)
            )
          ''');
        },
      );

      // Resolve profile dynamically to bypass host config file contamination
      DatabaseHelper.activeProfileOverride = 'Default';
      activeProfile = 'Default';

      // Set up instance database
      DatabaseHelper.instance.setDatabaseForTesting(db);

      // Insert mock profile and templates matching the active profile name
      await db.insert('profiles', {
        'name': activeProfile,
        'created_at': DateTime.now().toIso8601String(),
      });

      await db.insert('workout_templates', {
        'profile_name': activeProfile,
        'template_name': 'Morning HIIT Blast',
        'rounds': 10,
        'work_time': 40,
        'rest_time': 20,
        'notes': 'Fast intervals',
        'continuous_mode': 0,
        'activity_type': 'HIIT',
      });

      await db.insert('workout_templates', {
        'profile_name': activeProfile,
        'template_name': 'Heavy Squat Strength',
        'rounds': 5,
        'work_time': 120,
        'rest_time': 120,
        'notes': '5x5 target',
        'continuous_mode': 0,
        'activity_type': 'STRENGTH',
      });
    });

    tearDown(() async {
      DatabaseHelper.activeProfileOverride = null;
      await db.close();
    });

    Future<void> waitForDatabase(WidgetTester tester) async {
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('LibraryScreen renders template cards and filters', (tester) async {
      // Build our app and trigger a frame
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          onWorkoutSelected: (_) {},
        ),
      ));

      // Wait for database load to complete and UI to refresh
      await waitForDatabase(tester);

      // Verify the app bar title and profile tag are rendered
      expect(find.text('Workout Library'), findsOneWidget);
      expect(find.text(activeProfile), findsOneWidget);

      // Verify that both workout cards are displayed
      expect(find.text('Morning HIIT Blast'), findsOneWidget);
      expect(find.text('Heavy Squat Strength'), findsOneWidget);

      // Verify stats values are shown (Morning HIIT has 10 rounds, Squat has 5)
      expect(find.textContaining('10 Rounds'), findsOneWidget);
      expect(find.textContaining('5 Rounds'), findsOneWidget);
    });

    testWidgets('LibraryScreen search filters cards correctly', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          onWorkoutSelected: (_) {},
        ),
      ));
      await waitForDatabase(tester);

      // Type "Morning" into search box
      await tester.enterText(find.byType(TextField), 'Morning');
      await tester.pump();

      // HIIT card should be present, Strength card should be filtered out
      expect(find.text('Morning HIIT Blast'), findsOneWidget);
      expect(find.text('Heavy Squat Strength'), findsNothing);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      // Both should appear again
      expect(find.text('Morning HIIT Blast'), findsOneWidget);
      expect(find.text('Heavy Squat Strength'), findsOneWidget);
    });

    testWidgets('LibraryScreen category pills filter cards correctly', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          onWorkoutSelected: (_) {},
        ),
      ));
      await waitForDatabase(tester);

      // Tap on "Strength Training" filter chip uniquely
      await tester.tap(find.widgetWithText(ChoiceChip, 'Strength Training'));
      await tester.pumpAndSettle();

      // Strength card should be present, HIIT card should be filtered out
      expect(find.text('Heavy Squat Strength'), findsOneWidget);
      expect(find.text('Morning HIIT Blast'), findsNothing);
    });

    testWidgets('LibraryScreen selecting template fires onWorkoutSelected callback', (tester) async {
      // Set larger viewport to avoid scrolling issues
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Map<String, dynamic>? selectedTemplate;

      await tester.pumpWidget(MaterialApp(
        home: LibraryScreen(
          onWorkoutSelected: (template) {
            selectedTemplate = template;
          },
        ),
      ));
      await waitForDatabase(tester);

      // Find the card containing 'Heavy Squat Strength' and tap its Start button
      final squatCard = find.ancestor(
        of: find.text('Heavy Squat Strength'),
        matching: find.byType(Card),
      );
      final startButton = find.descendant(
        of: squatCard,
        matching: find.text('Start'),
      );
      await tester.tap(startButton);
      await tester.pump();

      expect(selectedTemplate, isNotNull);
      expect(selectedTemplate!['template_name'], equals('Heavy Squat Strength'));
      expect(selectedTemplate!['rounds'], equals(5));
      expect(selectedTemplate!['work_time'], equals(120));
      expect(selectedTemplate!['rest_time'], equals(120));
    });
  });
}

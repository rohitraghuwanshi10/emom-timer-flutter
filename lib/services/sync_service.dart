import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';

class SyncService extends ChangeNotifier {
  static final SyncService instance = SyncService._init();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;
  String? _lastError;
  String? get lastError => _lastError;
  String _syncStatus = "Idle";
  String get syncStatus => _syncStatus;

  SyncService._init();

  Future<void> deleteTemplateRemote(String profileName, String templateName) async {
    try {
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }
      final docId = '${profileName}_$templateName';
      await _firestore.collection('templates').doc(docId).delete();
      debugPrint('SyncService: Deleted template $docId from Firestore.');
    } catch (e) {
      debugPrint('SyncService: Error deleting template $templateName from Firestore: $e');
    }
  }

  Future<bool> signInAndSync() async {
    if (_isSyncing) {
      _lastError = "Sync already in progress (Status: $_syncStatus).";
      return false;
    }
    _isSyncing = true;
    _lastError = null;
    _syncStatus = "Starting...";
    notifyListeners();
    
    try {
      // 1. Silent anonymous login
      if (_auth.currentUser == null) {
        _syncStatus = "Signing in anonymously...";
        notifyListeners();
        debugPrint('SyncService: Signing in anonymously...');
        await _auth.signInAnonymously().timeout(const Duration(seconds: 15), onTimeout: () {
          throw Exception("Authentication timeout. Check your internet connection.");
        });
        debugPrint('SyncService: Logged in as User ID: ${_auth.currentUser?.uid}');
      }
      
      // 2. Perform the two-way sync
      _syncStatus = "Syncing database...";
      notifyListeners();
      await _syncData().timeout(const Duration(seconds: 25), onTimeout: () {
        throw Exception("Database sync timeout. Firestore connection took too long.");
      });
      
      _syncStatus = "Idle";
      _isSyncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      _syncStatus = "Error";
      _lastError = e.toString();
      debugPrint('SyncService: Error during sync: $e');
      _isSyncing = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _syncData() async {
    final db = await DatabaseHelper.instance.database;
    debugPrint('SyncService: Starting database sync...');

    // ----------------------------------------------------
    // 1. SYNC PROFILES
    // ----------------------------------------------------
    _syncStatus = "Syncing profiles...";
    notifyListeners();
    final localProfiles = await db.query('profiles');
    
    // Upload local profiles to Firestore
    for (var local in localProfiles) {
      final name = local['name'] as String;
      await _firestore.collection('profiles').doc(name).set({
        'name': name,
        'created_at': local['created_at'],
        'max_hr': local['max_hr'],
        'max_prework_hr': local['max_prework_hr'],
        'sex': local['sex'],
        'birth_date': local['birth_date'],
        'weight_kg': local['weight_kg'],
        'weight_unit_pref': local['weight_unit_pref'],
        'distance_unit_pref': local['distance_unit_pref'] ?? 'km',
        'auto_connect_hr': local['auto_connect_hr'],
        'save_history': local['save_history'] ?? 1,
        'treadmill_enabled': local['treadmill_enabled'] ?? 0,
        'treadmill_preset_1': local['treadmill_preset_1'] ?? 2.0,
        'treadmill_preset_2': local['treadmill_preset_2'] ?? 4.0,
        'treadmill_preset_3': local['treadmill_preset_3'] ?? 6.0,
      }, SetOptions(merge: true));
    }

    // Download remote profiles from Firestore
    final remoteProfiles = await _firestore.collection('profiles').get();
    for (var doc in remoteProfiles.docs) {
      final name = doc.id;
      final data = doc.data();
      final exists = localProfiles.any((p) => p['name'] == name);
      
      if (!exists) {
        await db.insert('profiles', {
          'name': name,
          'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
          'max_hr': data['max_hr'],
          'max_prework_hr': data['max_prework_hr'],
          'sex': data['sex'],
          'birth_date': data['birth_date'],
          'weight_kg': data['weight_kg'],
          'weight_unit_pref': data['weight_unit_pref'],
          'distance_unit_pref': data['distance_unit_pref'] ?? 'km',
          'auto_connect_hr': data['auto_connect_hr'],
          'save_history': data['save_history'] ?? 1,
          'treadmill_enabled': data['treadmill_enabled'] ?? 0,
          'treadmill_preset_1': data['treadmill_preset_1'] ?? 2.0,
          'treadmill_preset_2': data['treadmill_preset_2'] ?? 4.0,
          'treadmill_preset_3': data['treadmill_preset_3'] ?? 6.0,
        });
        debugPrint('SyncService: Downloaded profile $name');
      } else {
        // Update local profile details from Firestore
        final updateData = <String, dynamic>{
          'max_hr': data['max_hr'],
          'max_prework_hr': data['max_prework_hr'],
          'sex': data['sex'],
          'birth_date': data['birth_date'],
          'weight_kg': data['weight_kg'],
          'weight_unit_pref': data['weight_unit_pref'],
          'auto_connect_hr': data['auto_connect_hr'],
        };
        if (data.containsKey('distance_unit_pref')) {
          updateData['distance_unit_pref'] = data['distance_unit_pref'] ?? 'km';
        }
        if (data.containsKey('save_history')) {
          updateData['save_history'] = data['save_history'] ?? 1;
        }
        if (data.containsKey('treadmill_enabled')) {
          updateData['treadmill_enabled'] = data['treadmill_enabled'] ?? 0;
        }
        if (data.containsKey('treadmill_preset_1')) {
          updateData['treadmill_preset_1'] = data['treadmill_preset_1'] ?? 2.0;
        }
        if (data.containsKey('treadmill_preset_2')) {
          updateData['treadmill_preset_2'] = data['treadmill_preset_2'] ?? 4.0;
        }
        if (data.containsKey('treadmill_preset_3')) {
          updateData['treadmill_preset_3'] = data['treadmill_preset_3'] ?? 6.0;
        }
        await db.update('profiles', updateData, where: 'name = ?', whereArgs: [name]);
      }
    }

    // ----------------------------------------------------
    // 2. SYNC WORKOUT TEMPLATES
    // ----------------------------------------------------
    _syncStatus = "Syncing templates...";
    notifyListeners();
    final localTemplates = await db.query('workout_templates');
    
    // Upload local templates to Firestore
    for (var local in localTemplates) {
      final pName = local['profile_name'] as String;
      final tName = local['template_name'] as String;
      final docId = '${pName}_$tName';
      
      await _firestore.collection('templates').doc(docId).set({
        'profile_name': pName,
        'template_name': tName,
        'rounds': local['rounds'],
        'work_time': local['work_time'],
        'rest_time': local['rest_time'],
        'notes': local['notes'],
        'continuous_mode': local['continuous_mode'] ?? 0,
        'activity_type': local['activity_type'] ?? 'HIIT',
        'auto_regulate': local['auto_regulate'] ?? 1,
        'treadmill_workout': local['treadmill_workout'] ?? 0,
        'work_speed': local['work_speed'] ?? 4.0,
        'rest_speed': local['rest_speed'] ?? 0.0,
      }, SetOptions(merge: true));
    }

    // Download remote templates from Firestore
    final remoteTemplates = await _firestore.collection('templates').get();
    for (var doc in remoteTemplates.docs) {
      final data = doc.data();
      final pName = data['profile_name'] as String;
      final tName = data['template_name'] as String;
      
      final exists = localTemplates.any((t) => t['profile_name'] == pName && t['template_name'] == tName);
      if (!exists) {
        await db.insert('workout_templates', {
          'profile_name': pName,
          'template_name': tName,
          'rounds': data['rounds'],
          'work_time': data['work_time'],
          'rest_time': data['rest_time'],
          'notes': data['notes'],
          'continuous_mode': data['continuous_mode'] ?? 0,
          'activity_type': data['activity_type'] ?? 'HIIT',
          'auto_regulate': data['auto_regulate'] ?? 1,
          'treadmill_workout': data['treadmill_workout'] ?? 0,
          'work_speed': data['work_speed'] ?? 4.0,
          'rest_speed': data['rest_speed'] ?? 0.0,
        });
        debugPrint('SyncService: Downloaded template $tName for profile $pName');
      } else {
        // Update local template settings from Firestore
        final updateMap = <String, dynamic>{
          'rounds': data['rounds'],
          'work_time': data['work_time'],
          'rest_time': data['rest_time'],
          'notes': data['notes'],
        };
        if (data.containsKey('continuous_mode')) {
          updateMap['continuous_mode'] = data['continuous_mode'] ?? 0;
        }
        if (data.containsKey('activity_type')) {
          updateMap['activity_type'] = data['activity_type'] ?? 'HIIT';
        }
        if (data.containsKey('auto_regulate')) {
          updateMap['auto_regulate'] = data['auto_regulate'] ?? 1;
        }
        if (data.containsKey('treadmill_workout')) {
          updateMap['treadmill_workout'] = data['treadmill_workout'] ?? 0;
        }
        if (data.containsKey('work_speed')) {
          updateMap['work_speed'] = data['work_speed'] ?? 4.0;
        }
        if (data.containsKey('rest_speed')) {
          updateMap['rest_speed'] = data['rest_speed'] ?? 0.0;
        }
        await db.update('workout_templates', updateMap,
            where: 'profile_name = ? AND template_name = ?',
            whereArgs: [pName, tName]);
      }
    }

    // 3. SYNC WORKOUTS & HEART RATE LOGS
    // ----------------------------------------------------
    _syncStatus = "Syncing workouts...";
    notifyListeners();
    final localWorkouts = await db.query('workouts');
    
    // Get all remote workout document data to check for updates (e.g. edited notes)
    final remoteWorkoutsSnap = await _firestore.collection('workouts').get();
    final Map<String, Map<String, dynamic>> remoteWorkoutsMap = {
      for (var doc in remoteWorkoutsSnap.docs) doc.id: doc.data()
    };
    final Set<String> remoteDocIds = remoteWorkoutsMap.keys.toSet();
    
    // Upload local workouts that are missing in Firestore or have updated notes
    for (var w in localWorkouts) {
      final pName = w['profile_name'] as String;
      final sTime = w['start_time'] as String;
      final docId = '${pName}_$sTime';
      
      if (!remoteDocIds.contains(docId)) {
        debugPrint('SyncService: Uploading workout: $docId...');
        // Fetch heart rate logs for this workout
        final hrLogs = await db.query(
          'heart_rate_logs',
          where: 'workout_id = ?',
          whereArgs: [w['id']],
          orderBy: 'capture_time ASC'
        );
        
        final hrDataList = hrLogs.map((log) => {
          'capture_time': log['capture_time'],
          'bpm': log['bpm'],
          'zone': log['zone'],
        }).toList();

        await _firestore.collection('workouts').doc(docId).set({
          'profile_name': pName,
          'workout_name': w['workout_name'] ?? '',
          'start_time': sTime,
          'end_time': w['end_time'],
          'total_rounds_completed': w['total_rounds_completed'],
          'work_duration': w['work_duration'],
          'rest_duration': w['rest_duration'],
          'total_time_sec': w['total_time_sec'],
          'work_time_sec': w['work_time_sec'],
          'rest_time_sec': w['rest_time_sec'],
          'max_hr': w['max_hr'],
          'avg_hr': w['avg_hr'],
          'calories_burnt_kcal': w['calories_burnt_kcal'],
          'notes': w['notes'],
          'activity_type': w['activity_type'] ?? 'HIIT',
          'run_distance': w['run_distance'] ?? 0.0,
          'run_peak_speed': w['run_peak_speed'] ?? 0.0,
          'run_avg_speed': w['run_avg_speed'] ?? 0.0,
          'hr_details': hrDataList,
        });
        
        // Add to our list and map so we track it as synced
        remoteDocIds.add(docId);
        remoteWorkoutsMap[docId] = {
          'profile_name': pName,
          'start_time': sTime,
          'notes': w['notes'],
        };
      } else {
        final remoteData = remoteWorkoutsMap[docId];
        if (remoteData != null) {
          final remoteNotes = remoteData['notes'] as String? ?? '';
          final localNotes = w['notes'] as String? ?? '';
          if (localNotes != remoteNotes && localNotes.isNotEmpty) {
            debugPrint('SyncService: Updating remote workout notes for: $docId...');
            await _firestore.collection('workouts').doc(docId).update({
              'notes': localNotes,
            });
            remoteData['notes'] = localNotes;
          }
        }
      }
    }

    // Download remote workouts that are missing locally or have updated notes
    for (var doc in remoteWorkoutsSnap.docs) {
      final docId = doc.id;
      final data = doc.data();
      final pName = data['profile_name'] as String;
      final sTime = data['start_time'] as String;
      
      Map<String, dynamic>? localW;
      for (var w in localWorkouts) {
        if (w['profile_name'] == pName && w['start_time'] == sTime) {
          localW = w;
          break;
        }
      }
      
      if (localW == null) {
        debugPrint('SyncService: Downloading workout: $docId...');
        await db.transaction((txn) async {
          final workoutId = await txn.insert('workouts', {
            'profile_name': pName,
            'workout_name': data['workout_name'] ?? '',
            'start_time': sTime,
            'end_time': data['end_time'],
            'total_rounds_completed': data['total_rounds_completed'],
            'work_duration': data['work_duration'],
            'rest_duration': data['rest_duration'],
            'total_time_sec': data['total_time_sec'],
            'work_time_sec': data['work_time_sec'],
            'rest_time_sec': data['rest_time_sec'],
            'max_hr': data['max_hr'],
            'avg_hr': data['avg_hr'],
            'calories_burnt_kcal': data['calories_burnt_kcal'],
            'notes': data['notes'],
            'activity_type': data['activity_type'] ?? 'HIIT',
            'run_distance': data['run_distance'] ?? 0.0,
            'run_peak_speed': data['run_peak_speed'] ?? 0.0,
            'run_avg_speed': data['run_avg_speed'] ?? 0.0,
          });
          
          final List<dynamic> hrDetails = data['hr_details'] ?? [];
          for (var log in hrDetails) {
            await txn.insert('heart_rate_logs', {
              'workout_id': workoutId,
              'capture_time': log['capture_time'],
              'bpm': log['bpm'],
              'zone': log['zone'],
            });
          }
        });
      } else {
        final localNotes = localW['notes'] as String? ?? '';
        final remoteNotes = data['notes'] as String? ?? '';
        if (localNotes != remoteNotes && localNotes.isEmpty && remoteNotes.isNotEmpty) {
          debugPrint('SyncService: Downloading updated notes for $docId...');
          await db.update(
            'workouts',
            {'notes': remoteNotes},
            where: 'id = ?',
            whereArgs: [localW['id']],
          );
        }
      }
    }

    debugPrint('SyncService: Database sync completed successfully.');
  }
}

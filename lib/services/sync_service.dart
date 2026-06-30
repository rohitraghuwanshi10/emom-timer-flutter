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
    
    // Download remote profiles from Firestore first so we can do a smart conflict merge
    final remoteProfilesSnapshot = await _firestore.collection('profiles').get();
    final remoteProfilesMap = {for (var doc in remoteProfilesSnapshot.docs) doc.id: doc.data()};

    // Keep track of names we have processed
    final processedNames = <String>{};

    for (var local in localProfiles) {
      final name = local['name'] as String;
      processedNames.add(name);

      final localUpdatedAtStr = local['updated_at'] as String?;
      final localUpdatedAt = localUpdatedAtStr != null ? DateTime.tryParse(localUpdatedAtStr) : null;

      final remoteData = remoteProfilesMap[name];
      
      if (remoteData != null) {
        final remoteUpdatedAtStr = remoteData['updated_at'] as String?;
        final remoteUpdatedAt = remoteUpdatedAtStr != null ? DateTime.tryParse(remoteUpdatedAtStr) : null;

        // If local is newer, upload local to remote. If remote is newer, download remote.
        if (localUpdatedAt == null || (remoteUpdatedAt != null && remoteUpdatedAt.isAfter(localUpdatedAt))) {
          // Remote is newer, download remote to local
          final updateData = <String, dynamic>{
            'max_hr': remoteData['max_hr'],
            'max_prework_hr': remoteData['max_prework_hr'],
            'sex': remoteData['sex'],
            'birth_date': remoteData['birth_date'],
            'weight_kg': remoteData['weight_kg'],
            'weight_unit_pref': remoteData['weight_unit_pref'],
            'auto_connect_hr': remoteData['auto_connect_hr'],
            'updated_at': remoteUpdatedAtStr,
          };
          if (remoteData.containsKey('distance_unit_pref')) {
            updateData['distance_unit_pref'] = remoteData['distance_unit_pref'] ?? 'km';
          }
          if (remoteData.containsKey('save_history')) {
            updateData['save_history'] = remoteData['save_history'] ?? 1;
          }
          if (remoteData.containsKey('treadmill_enabled')) {
            updateData['treadmill_enabled'] = remoteData['treadmill_enabled'] ?? 0;
          }
          if (remoteData.containsKey('treadmill_preset_1')) {
            updateData['treadmill_preset_1'] = remoteData['treadmill_preset_1'] ?? 2.0;
          }
          if (remoteData.containsKey('treadmill_preset_2')) {
            updateData['treadmill_preset_2'] = remoteData['treadmill_preset_2'] ?? 4.0;
          }
          if (remoteData.containsKey('treadmill_preset_3')) {
            updateData['treadmill_preset_3'] = remoteData['treadmill_preset_3'] ?? 6.0;
          }
          await db.update('profiles', updateData, where: 'name = ?', whereArgs: [name]);
          debugPrint('SyncService: Downloaded newer profile $name from Firestore.');
        } else {
          // Local is newer, upload local to remote
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
            'updated_at': localUpdatedAtStr,
          }, SetOptions(merge: true));
          debugPrint('SyncService: Uploaded newer profile $name to Firestore.');
        }
      } else {
        // Remote does not exist, upload local to remote
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
          'updated_at': localUpdatedAtStr ?? DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
        debugPrint('SyncService: Uploaded new profile $name to Firestore.');
      }
    }

    // Download remote profiles that do not exist locally
    for (var entry in remoteProfilesMap.entries) {
      final name = entry.key;
      final data = entry.value;
      if (!processedNames.contains(name)) {
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
          'updated_at': data['updated_at'],
        });
        debugPrint('SyncService: Downloaded remote-only profile $name');
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
        'weight_moved': local['weight_moved'] ?? 0.0,
        'weight_unit': local['weight_unit'] ?? 'kg',
        'ruck_weight': local['ruck_weight'] ?? 0.0,
        'ruck_weight_unit': local['ruck_weight_unit'] ?? 'lbs',
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
          'weight_moved': data['weight_moved'] ?? 0.0,
          'weight_unit': data['weight_unit'] ?? 'kg',
          'ruck_weight': data['ruck_weight'] ?? 0.0,
          'ruck_weight_unit': data['ruck_weight_unit'] ?? 'lbs',
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
        if (data.containsKey('weight_moved')) {
          updateMap['weight_moved'] = data['weight_moved'] ?? 0.0;
        }
        if (data.containsKey('weight_unit')) {
          updateMap['weight_unit'] = data['weight_unit'] ?? 'kg';
        }
        if (data.containsKey('ruck_weight')) {
          updateMap['ruck_weight'] = data['ruck_weight'] ?? 0.0;
        }
        if (data.containsKey('ruck_weight_unit')) {
          updateMap['ruck_weight_unit'] = data['ruck_weight_unit'] ?? 'lbs';
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
          'weight_moved': w['weight_moved'] ?? 0.0,
          'weight_unit': w['weight_unit'] ?? 'kg',
          'total_weight_moved': w['total_weight_moved'] ?? 0.0,
          'ruck_weight': w['ruck_weight'] ?? 0.0,
          'ruck_weight_unit': w['ruck_weight_unit'] ?? 'lbs',
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
            'weight_moved': data['weight_moved'] ?? 0.0,
            'weight_unit': data['weight_unit'] ?? 'kg',
            'total_weight_moved': data['total_weight_moved'] ?? 0.0,
            'ruck_weight': data['ruck_weight'] ?? 0.0,
            'ruck_weight_unit': data['ruck_weight_unit'] ?? 'lbs',
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
        
        final localWeight = (localW['weight_moved'] as num?)?.toDouble() ?? 0.0;
        final remoteWeight = (data['weight_moved'] as num?)?.toDouble() ?? 0.0;
        final localRuck = (localW['ruck_weight'] as num?)?.toDouble() ?? 0.0;
        final remoteRuck = (data['ruck_weight'] as num?)?.toDouble() ?? 0.0;

        final updateMap = <String, dynamic>{};
        
        if (localNotes != remoteNotes && localNotes.isEmpty && remoteNotes.isNotEmpty) {
          updateMap['notes'] = remoteNotes;
        }
        
        if (localWeight == 0.0 && remoteWeight > 0.0) {
          updateMap['weight_moved'] = remoteWeight;
          updateMap['weight_unit'] = data['weight_unit'] ?? 'kg';
          updateMap['total_weight_moved'] = (data['total_weight_moved'] as num?)?.toDouble() ?? 0.0;
        }
        
        if (localRuck == 0.0 && remoteRuck > 0.0) {
          updateMap['ruck_weight'] = remoteRuck;
          updateMap['ruck_weight_unit'] = data['ruck_weight_unit'] ?? 'lbs';
        }
        
        if (updateMap.isNotEmpty) {
          debugPrint('SyncService: Downloading updated fields for $docId: $updateMap');
          await db.update(
            'workouts',
            updateMap,
            where: 'id = ?',
            whereArgs: [localW['id']],
          );
        }
      }
    }

    debugPrint('SyncService: Database sync completed successfully.');
  }
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

class HealthService {
  static final HealthService instance = HealthService._init();
  final Health _health = Health();
  bool _isConfigured = false;

  HealthService._init();

  final List<HealthDataType> _types = [
    HealthDataType.WORKOUT,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.HEART_RATE,
  ];

  Future<void> _ensureConfigured() async {
    if (_isConfigured) return;
    try {
      await _health.configure();
      _isConfigured = true;
    } catch (e) {
      debugPrint("HealthService: Error configuring Health plugin: $e");
    }
  }

  Future<bool> requestPermissions() async {
    if (Platform.isMacOS) return false;
    await _ensureConfigured();

    try {
      final permissions = _types.map((_) => HealthDataAccess.READ_WRITE).toList();
      bool granted = await _health.requestAuthorization(_types, permissions: permissions);
      debugPrint("HealthService: permissions requested. Result: $granted");
      return granted;
    } catch (e) {
      debugPrint("HealthService: Error requesting permissions: $e");
      return false;
    }
  }

  Future<void> saveWorkout({
    required DateTime start,
    required DateTime end,
    required int totalCalories,
    required String title,
    List<Map<String, dynamic>> heartRateData = const [],
  }) async {
    if (Platform.isMacOS) return;
    await _ensureConfigured();

    try {
      // Prompt/check authorization silently (or request if not yet granted)
      final permissions = _types.map((_) => HealthDataAccess.READ_WRITE).toList();
      bool hasAuth = await _health.requestAuthorization(_types, permissions: permissions);
      if (!hasAuth) {
        debugPrint("HealthService: No write permission. Skipping Apple Health save.");
        return;
      }

      debugPrint("HealthService: Writing workout to Apple Health/Health Connect...");
      
      // Determine activity type - default to HIIT
      final activityType = HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING;

      bool workoutSaved = await _health.writeWorkoutData(
        activityType: activityType,
        start: start,
        end: end,
        totalEnergyBurned: totalCalories,
        title: title,
      );

      if (workoutSaved) {
        debugPrint("HealthService: Workout successfully saved to Health app!");

        // Write individual heart rate logs if present
        if (heartRateData.isNotEmpty) {
          debugPrint("HealthService: Writing ${heartRateData.length} heart rate points to Health app...");
          for (var log in heartRateData) {
            try {
              final captureTime = DateTime.parse(log['capture_time'] as String);
              final bpm = (log['bpm'] as num).toDouble();
              
              await _health.writeHealthData(
                value: bpm,
                type: HealthDataType.HEART_RATE,
                startTime: captureTime,
                endTime: captureTime,
              );
            } catch (hrError) {
              debugPrint("HealthService: Error writing individual heart rate sample: $hrError");
            }
          }
        }
      } else {
        debugPrint("HealthService: Health plugin returned false when writing workout.");
      }
    } catch (e) {
      debugPrint("HealthService: Error saving workout to Apple Health: $e");
    }
  }
}

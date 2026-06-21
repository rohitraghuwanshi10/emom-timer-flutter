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

  final List<HealthDataType> _readOnlyTypes = [
    HealthDataType.GENDER,
    HealthDataType.BIRTH_DATE,
    HealthDataType.WEIGHT,
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
      final allTypes = [..._types, ..._readOnlyTypes];
      final permissions = [
        ..._types.map((_) => HealthDataAccess.READ_WRITE),
        ..._readOnlyTypes.map((_) => HealthDataAccess.READ),
      ];
      bool granted = await _health.requestAuthorization(allTypes, permissions: permissions);
      debugPrint("HealthService: permissions requested. Result: $granted");
      return granted;
    } catch (e) {
      debugPrint("HealthService: Error requesting permissions: $e");
      return false;
    }
  }

  Future<Map<String, String?>> getCharacteristics() async {
    if (Platform.isMacOS) return {};
    await _ensureConfigured();

    try {
      final now = DateTime.now();
      // query the last 5 years to capture weight samples even if infrequently logged
      final data = await _health.getHealthDataFromTypes(
        types: _readOnlyTypes,
        startTime: now.subtract(const Duration(days: 1825)),
        endTime: now,
      );

      String? sex;
      String? birthDate;
      double? weight;
      DateTime? latestWeightTime;

      debugPrint("HealthService: getCharacteristics raw data points count: ${data.length}");
      for (var point in data) {
        debugPrint("HealthService: Raw point: type=${point.type}, value=${point.value} (${point.value.runtimeType})");
        if (point.type == HealthDataType.GENDER) {
          final val = point.value;
          num? numericVal;
          if (val is NumericHealthValue) {
            numericVal = val.numericValue;
          } else if (val is num) {
            numericVal = val as num;
          }
          
          if (numericVal != null && numericVal != 0) {
            if (numericVal == 1) sex = "Female";
            if (numericVal == 2) sex = "Male";
          } else {
            final str = val.toString().toLowerCase();
            if (str.contains("female")) {
              sex = "Female";
            } else if (str.contains("male")) {
              sex = "Male";
            }
          }
        } else if (point.type == HealthDataType.BIRTH_DATE) {
          final val = point.value;
          num? numericVal;
          if (val is NumericHealthValue) {
            numericVal = val.numericValue;
          } else if (val is num) {
            numericVal = val as num;
          }
          
          if (numericVal != null && numericVal != 0) {
            final dt = DateTime.fromMillisecondsSinceEpoch((numericVal * 1000).round());
            birthDate = dt.toIso8601String().substring(0, 10);
          } else {
            try {
              final parsedDate = DateTime.parse(val.toString());
              birthDate = parsedDate.toIso8601String().substring(0, 10);
            } catch (_) {
              final str = val.toString();
              if (str.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(str)) {
                birthDate = str.substring(0, 10);
              }
            }
          }
        } else if (point.type == HealthDataType.WEIGHT) {
          final val = point.value;
          num? numericVal;
          if (val is NumericHealthValue) {
            numericVal = val.numericValue;
          } else if (val is num) {
            numericVal = val as num;
          }
          
          if (numericVal != null && numericVal != 0) {
            if (latestWeightTime == null || point.dateTo.isAfter(latestWeightTime)) {
              latestWeightTime = point.dateTo;
              weight = numericVal.toDouble();
            }
          }
        }
      }

      debugPrint("HealthService: Fetched characteristics from Apple Health: sex=$sex, birthDate=$birthDate, weight=$weight");
      return {
        'sex': sex,
        'birth_date': birthDate,
        'weight': weight?.toStringAsFixed(1),
      };
    } catch (e) {
      debugPrint("HealthService: Error fetching characteristics: $e");
      return {};
    }
  }

  HealthWorkoutActivityType _mapStringToActivityType(String? typeStr) {
    if (typeStr == null) return HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING;
    switch (typeStr) {
      case 'HIIT':
        return HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING;
      case 'STRENGTH':
        return HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING;
      case 'FUNCTIONAL_STRENGTH':
        return HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING;
      case 'CORE':
        return HealthWorkoutActivityType.CORE_TRAINING;
      case 'CARDIO':
        return HealthWorkoutActivityType.MIXED_CARDIO;
      case 'YOGA':
        return HealthWorkoutActivityType.YOGA;
      case 'PILATES':
        return HealthWorkoutActivityType.PILATES;
      case 'CALISTHENICS':
        return HealthWorkoutActivityType.CALISTHENICS;
      case 'OTHER':
      default:
        return HealthWorkoutActivityType.OTHER;
    }
  }

  Future<void> saveWorkout({
    required DateTime start,
    required DateTime end,
    required int totalCalories,
    required String title,
    List<Map<String, dynamic>> heartRateData = const [],
    String? activityTypeStr,
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
      
      // Determine activity type
      final activityType = _mapStringToActivityType(activityTypeStr);

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

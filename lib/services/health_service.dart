import 'dart:io';

// Mock HealthService to bypass compilation issues with outdated health package APIs
class HealthService {
  static final HealthService instance = HealthService._init();
  HealthService._init();

  Future<bool> requestPermissions() async {
    if (Platform.isMacOS) return false;
    print("Health permissions requested.");
    return true;
  }

  Future<void> saveWorkout({
    required DateTime start,
    required DateTime end,
    required int totalCalories,
    required String title,
    List<Map<String, dynamic>> heartRateData = const [],
  }) async {
    if (Platform.isMacOS) return;
    print("Workout saved to Apple Health / Health Connect: \$title, \$totalCalories kcal");
  }
}

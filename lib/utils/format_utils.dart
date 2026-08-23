class FormatUtils {
  FormatUtils._();

  /// Converts duration in seconds to standard MM:SS string (e.g. 05:30)
  static String formatDuration(int seconds) {
    if (seconds < 0) seconds = 0;
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Converts duration in seconds to readable concise string (e.g. "2m 30s", "45s", "None")
  static String formatDurationConcise(int seconds, {String zeroText = 'None'}) {
    if (seconds <= 0) return zeroText;
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    if (minutes > 0 && remainingSeconds > 0) {
      return '${minutes}m ${remainingSeconds}s';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else {
      return '${remainingSeconds}s';
    }
  }

  /// Formats speed according to metric/imperial preference
  static String formatSpeed(double speedKmh, {bool isMetric = true, int decimals = 1}) {
    final double displaySpeed = isMetric ? speedKmh : speedKmh * 0.621371;
    final String unit = isMetric ? 'km/h' : 'mph';
    return '${displaySpeed.toStringAsFixed(decimals)} $unit';
  }

  /// Formats distance according to metric/imperial preference
  static String formatDistance(double distanceKm, {bool isMetric = true, int decimals = 2}) {
    final double displayDist = isMetric ? distanceKm : distanceKm * 0.621371;
    final String unit = isMetric ? 'km' : 'mi';
    return '${displayDist.toStringAsFixed(decimals)} $unit';
  }

  /// Formats weight with unit
  static String formatWeight(double weight, String unit, {int decimals = 1}) {
    if (weight <= 0) return '0 $unit';
    return '${weight.toStringAsFixed(decimals)} $unit';
  }

  /// Converts km/h to mph
  static double kmhToMph(double kmh) => kmh * 0.621371;

  /// Converts mph to km/h
  static double mphToKmh(double mph) => mph * 1.60934;

  /// Converts user age based on an ISO birthdate string (e.g., "1990-05-15")
  static int calculateAge(String? birthDateStr) {
    if (birthDateStr == null || birthDateStr.isEmpty) return 35; // Default fallback
    try {
      final birth = DateTime.parse(birthDateStr);
      final today = DateTime.now();
      int age = today.year - birth.year;
      if (today.month < birth.month || (today.month == birth.month && today.day < birth.day)) {
        age--;
      }
      return age.clamp(10, 120);
    } catch (_) {
      return 35;
    }
  }

  // ----------------------------------------------------
  // Workout Parameter Slider & Stepper Calculations
  // ----------------------------------------------------

  static double secondsToWorkSliderValue(int seconds) {
    if (seconds <= 300) {
      final pct = (seconds - 10) / (300 - 10);
      return pct * 0.5;
    } else {
      final pct = (seconds - 300) / (3600 - 300);
      return 0.5 + pct * 0.5;
    }
  }

  static int workSliderValueToSeconds(double value) {
    if (value <= 0.5) {
      final pct = value / 0.5;
      final seconds = 10 + (300 - 10) * pct;
      return ((seconds / 5).round() * 5).clamp(10, 300);
    } else {
      final pct = (value - 0.5) / 0.5;
      final seconds = 300 + (3600 - 300) * pct;
      return ((seconds / 60).round() * 60).clamp(300, 3600);
    }
  }

  static int decrementWorkDuration(int current) {
    if (current <= 10) return 10;
    if (current <= 300) {
      return (current - 5).clamp(10, 3600);
    } else {
      final newDuration = ((current - 60) / 60).floor() * 60;
      return newDuration.clamp(300, 3600);
    }
  }

  static int incrementWorkDuration(int current) {
    if (current >= 3600) return 3600;
    if (current < 300) {
      return (current + 5).clamp(10, 3600);
    } else {
      final newDuration = ((current + 60) / 60).floor() * 60;
      return newDuration.clamp(300, 3600);
    }
  }

  static double secondsToRestSliderValue(int seconds) {
    if (seconds <= 120) {
      final pct = seconds / 120.0;
      return pct * 0.5;
    } else {
      final pct = (seconds - 120) / (900.0 - 120.0);
      return 0.5 + pct * 0.5;
    }
  }

  static int restSliderValueToSeconds(double value) {
    if (value <= 0.5) {
      final pct = value / 0.5;
      final seconds = 120.0 * pct;
      return ((seconds / 5).round() * 5).clamp(0, 120);
    } else {
      final pct = (value - 0.5) / 0.5;
      final seconds = 120.0 + (900.0 - 120.0) * pct;
      return ((seconds / 30).round() * 30).clamp(120, 900);
    }
  }

  static int decrementRestDuration(int current) {
    if (current <= 0) return 0;
    if (current <= 120) {
      return (current - 5).clamp(0, 900);
    } else {
      final newDuration = ((current - 30) / 30).floor() * 30;
      return newDuration.clamp(120, 900);
    }
  }

  static int incrementRestDuration(int current) {
    if (current >= 900) return 900;
    if (current < 120) {
      return (current + 5).clamp(0, 900);
    } else {
      final newDuration = ((current + 30) / 30).floor() * 30;
      return newDuration.clamp(120, 900);
    }
  }
}

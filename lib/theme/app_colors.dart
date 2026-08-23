import 'package:flutter/material.dart';

/// Central theme colors for ChronoPulse Active
class AppColors {
  AppColors._();

  static const Color deepBg = Color(0xFF0C101B);        // Deep Slate Charcoal Blue
  static const Color deepSurface = Color(0xFF171E2D);   // Deep Slate Card Surface
  static const Color mintNeon = Color(0xFF0DF2A3);      // Mint Neon Accent (Primary / Go)
  static const Color orangeNeon = Color(0xFFFF7A00);    // Vibrant Orange Accent (Secondary / Rest)
  static const Color redNeon = Color(0xFFFF3B30);       // Neon Red Accent (Stop/Error)
  static const Color textPrimary = Color(0xFFECEFF4);   // White Text
  static const Color textSecondary = Color(0xFF8E9AA8); // Slate Secondary Text
  static const Color cyan = Color(0xFF00E5FF);          // Cyan Accent (HRR / Telemetry)
  static const Color blue = Color(0xFF38B6FF);          // Zone / Accent Blue
  static const Color yellow = Color(0xFFFFD60A);        // Yellow
  static const Color purple = Color(0xFFBF5AF2);        // Purple

  static const List<Color> chartColors = [
    mintNeon,
    orangeNeon,
    blue,
    yellow,
    redNeon,
    purple,
  ];
}

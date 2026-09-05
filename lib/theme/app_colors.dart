import 'package:flutter/material.dart';

/// Central theme colors for ChronoPulse Active
class AppColors {
  AppColors._();

  // Dark Theme Tokens
  static const Color deepBg = Color(0xFF0C101B);        // Deep Slate Charcoal Blue
  static const Color deepSurface = Color(0xFF171E2D);   // Deep Slate Card Surface
  static const Color deepSurfaceCard = Color(0xFF1E2738); // Slightly lighter card container
  static const Color mintNeon = Color(0xFF0DF2A3);      // Mint Neon Accent (Primary / Go)
  static const Color orangeNeon = Color(0xFFFF7A00);    // Vibrant Orange Accent (Secondary / Rest)
  static const Color redNeon = Color(0xFFFF3B30);       // Neon Red Accent (Stop/Error)
  static const Color textPrimary = Color(0xFFECEFF4);   // White Text
  static const Color textSecondary = Color(0xFF8E9AA8); // Slate Secondary Text
  static const Color cyan = Color(0xFF00E5FF);          // Cyan Accent (HRR / Telemetry)
  static const Color blue = Color(0xFF38B6FF);          // Zone / Accent Blue
  static const Color yellow = Color(0xFFFFD60A);        // Yellow
  static const Color purple = Color(0xFFBF5AF2);        // Purple

  // Light Theme Tokens
  static const Color lightBg = Color(0xFFF4F6F9);       // Clean Soft Slate White
  static const Color lightSurface = Color(0xFFFFFFFF);  // Pure White Surface
  static const Color lightSurfaceCard = Color(0xFFF8FAFC); // Subtle card container
  static const Color lightSurfaceSubtle = Color(0xFFEDF2F7); // Subtle pill/action container
  static const Color lightTextPrimary = Color(0xFF0F172A); // Deep Slate Charcoal (14:1+ contrast, visible from 6-10ft)
  static const Color lightTextSecondary = Color(0xFF475569); // Slate secondary text
  static const Color lightTextTertiary = Color(0xFF94A3B8); // Slate muted text
  static const Color lightBorder = Color(0xFFE2E8F0);   // Subtle clean border
  static const Color mintLightPrimary = Color(0xFF059669); // Rich emerald mint (Primary / Go for Light Mode)
  static const Color orangeLightSecondary = Color(0xFFD97706); // Amber/orange (Secondary / Rest for Light Mode)
  static const Color redLight = Color(0xFFDC2626);      // Red for light mode
  static const Color cyanLight = Color(0xFF0284C7);     // Rich Blue/Cyan for light mode telemetry

  static const List<Color> chartColors = [
    mintNeon,
    orangeNeon,
    blue,
    yellow,
    redNeon,
    purple,
  ];

  static const List<Color> chartColorsLight = [
    mintLightPrimary,
    orangeLightSecondary,
    cyanLight,
    Color(0xFFCA8A04),
    redLight,
    Color(0xFF9333EA),
  ];
}

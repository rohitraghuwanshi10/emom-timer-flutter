import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.deepBg,
      primaryColor: AppColors.mintNeon,
      cardColor: AppColors.deepSurface,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.mintNeon,
        onPrimary: AppColors.deepBg,
        secondary: AppColors.orangeNeon,
        onSecondary: AppColors.deepBg,
        surface: AppColors.deepSurface,
        surfaceContainerHighest: AppColors.deepSurfaceCard,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        error: AppColors.redNeon,
        onError: AppColors.textPrimary,
        outline: Colors.white12,
        outlineVariant: Color(0xFF232E42),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.deepSurface,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.deepSurface,
        selectedItemColor: AppColors.mintNeon,
        unselectedItemColor: AppColors.textSecondary.withValues(alpha: 0.6),
      ),
      dividerTheme: const DividerThemeData(
        color: Colors.white12,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: AppColors.deepSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white12),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBg,
      primaryColor: AppColors.mintLightPrimary,
      cardColor: AppColors.lightSurface,
      colorScheme: const ColorScheme.light(
        primary: AppColors.mintLightPrimary,
        onPrimary: Colors.white,
        secondary: AppColors.orangeLightSecondary,
        onSecondary: Colors.white,
        surface: AppColors.lightSurface,
        surfaceContainerHighest: AppColors.lightSurfaceSubtle,
        onSurface: AppColors.lightTextPrimary,
        onSurfaceVariant: AppColors.lightTextSecondary,
        error: AppColors.redLight,
        onError: Colors.white,
        outline: AppColors.lightBorder,
        outlineVariant: Color(0xFFE2E8F0),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightSurface,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: AppColors.lightTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: AppColors.lightTextPrimary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        selectedItemColor: AppColors.mintLightPrimary,
        unselectedItemColor: AppColors.lightTextSecondary.withValues(alpha: 0.7),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightBorder,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.lightBorder),
        ),
      ),
    );
  }
}

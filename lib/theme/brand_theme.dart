import 'package:flutter/material.dart';

class BrandColors {
  // Primary accent — Solar Flare (human decision moments)
  static const primary = Color(0xFFF87040);

  // Surfaces — Terminal Dark elevation hierarchy
  static const background = Color(0xFF000000);  // Onyx Black
  static const surface = Color(0xFF141414);      // Graphite
  static const card = Color(0xFF1E1E1E);         // Charcoal
  static const border = Color(0xFF2A2A2A);       // Ash

  // Text hierarchy
  static const textPrimary = Color(0xFFFFFFFF);  // Pure White
  static const textSecondary = Color(0xFFB0B0B0); // Fog
  static const textDisabled = Color(0xFF606060);  // Smoke

  // Functional states
  static const success = Color(0xFF2ECC71);      // Crypto Green
  static const error = Color(0xFFE74C3C);        // Ember Red
  static const warning = Color(0xFFE2A93B);      // Tungsten
}

ThemeData buildBrandTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: BrandColors.primary,
      surface: BrandColors.surface,
      error: BrandColors.error,
    ),
    scaffoldBackgroundColor: BrandColors.background,
    cardTheme: const CardThemeData(
      color: BrandColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: BrandColors.border),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: BrandColors.surface,
      foregroundColor: BrandColors.textPrimary,
      elevation: 0,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: BrandColors.surface,
      selectedIconTheme: const IconThemeData(color: BrandColors.primary),
      unselectedIconTheme: const IconThemeData(color: BrandColors.textSecondary),
      selectedLabelTextStyle: const TextStyle(color: BrandColors.primary, fontSize: 12),
      unselectedLabelTextStyle: const TextStyle(color: BrandColors.textSecondary, fontSize: 12),
      indicatorColor: BrandColors.primary.withAlpha(30),
    ),
    dividerTheme: const DividerThemeData(color: BrandColors.border),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: BrandColors.textPrimary),
      headlineMedium: TextStyle(color: BrandColors.textPrimary),
      headlineSmall: TextStyle(color: BrandColors.textPrimary),
      titleLarge: TextStyle(color: BrandColors.textPrimary),
      titleMedium: TextStyle(color: BrandColors.textPrimary),
      titleSmall: TextStyle(color: BrandColors.textPrimary),
      bodyLarge: TextStyle(color: BrandColors.textPrimary),
      bodyMedium: TextStyle(color: BrandColors.textPrimary),
      bodySmall: TextStyle(color: BrandColors.textSecondary),
      labelLarge: TextStyle(color: BrandColors.textPrimary),
      labelMedium: TextStyle(color: BrandColors.textSecondary),
      labelSmall: TextStyle(color: BrandColors.textSecondary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BrandColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: BrandColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: BrandColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: BrandColors.primary),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: BrandColors.primary,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: BrandColors.textPrimary,
        side: const BorderSide(color: BrandColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
  );
}

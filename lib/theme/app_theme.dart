import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF062E34);
  static const deep = Color(0xFF021B21);
  static const ink = Color(0xFF123238);
  static const muted = Color(0xFF6B7C80);
  static const canvas = Color(0xFFF7FAF8);
  static const surface = Color(0xFFF2F7F4);
  static const surfaceAlt = Color(0xFFE7F1EB);
  static const green = Color(0xFF7DB9D8);
  static const greenDark = Color(0xFF2F6E92);
  static const danger = Color(0xFFF04465);
}

class AppAssets {
  static const logo = "assets/branding/stroyka_logo.svg";

  static const darkBackgrounds = [
    "assets/branding/bg_dark_workspace.jpg",
    "assets/branding/bg_dark_office.jpg",
    "assets/branding/bg_dark_tech.jpg",
    "assets/branding/bg_dark_pattern.jpg",
  ];

  static const lightTextures = [
    "assets/branding/texture_light_triangles.jpg",
    "assets/branding/texture_light_cloud.jpg",
    "assets/branding/texture_light_dots.jpg",
  ];
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.green,
        brightness: Brightness.light,
        primary: AppColors.green,
        secondary: AppColors.navy,
        surface: AppColors.canvas,
      ),
      fontFamily: "SF Pro Display",
    );

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      primaryColor: AppColors.green,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        iconTheme: IconThemeData(color: Colors.white),
        actionsIconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFDFEFD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.green, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.deep,
        selectedItemColor: AppColors.green,
        unselectedItemColor: Colors.white,
        selectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}

import 'package:flutter/material.dart';

class WebTheme {
  static const deep = Color(0xFF0E2430);
  static const ink = Color(0xFF18313D);
  static const muted = Color(0xFF63727C);
  static const green = Color(0xFF2E7D32);
  static const greenSoft = Color(0xFFEAF4EC);
  static const blueprint = Color(0xFF7DB9D8);
  static const border = Color(0xFFE3E9ED);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF5F8FA);
  static const page = Color(0xFFF1F5F7);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
        primary: green,
        surface: surface,
      ),
      scaffoldBackgroundColor: page,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: ink,
          fontSize: 28,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: ink,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(
          color: ink,
          fontSize: 14,
          height: 1.35,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: green, width: 1.4),
        ),
      ),
    );
  }
}

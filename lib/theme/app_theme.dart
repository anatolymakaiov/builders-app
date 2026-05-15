import 'package:flutter/material.dart';

import 'app_buttons.dart';
import 'app_colors.dart';
import 'app_input_fields.dart';
import 'app_typography.dart';

export 'app_buttons.dart';
export 'app_blueprint.dart';
export 'app_cards.dart';
export 'app_chips.dart';
export 'app_colors.dart';
export 'app_dropdown_menu.dart';
export 'app_input_fields.dart';
export 'app_profile_widgets.dart';
export 'app_spacing.dart';
export 'app_typography.dart';

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.blueprintLine,
        brightness: Brightness.light,
        primary: AppColors.blueprintLine,
        secondary: AppColors.navy,
        surface: AppColors.canvas,
      ),
      fontFamily: "SF Pro Display",
    );

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      primaryColor: AppColors.blueprintLine,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 24,
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
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: AppColors.blueprintLine.withValues(alpha: 0.64),
          ),
        ),
      ),
      inputDecorationTheme: AppInputFields.theme(),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: AppButtonStyles.primary(),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: AppButtonStyles.secondary(),
      ),
      textButtonTheme: TextButtonThemeData(
        style: AppButtonStyles.text(),
      ),
      tabBarTheme: const TabBarThemeData(
        labelStyle: AppTypography.tab,
        unselectedLabelStyle: AppTypography.tabUnselected,
        labelColor: AppColors.greenDark,
        unselectedLabelColor: AppColors.muted,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        elevation: 14,
        shadowColor: Colors.black.withValues(alpha: 0.32),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: AppColors.blueprintLine.withValues(alpha: 0.35),
          ),
        ),
        textStyle: AppTypography.body.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.deep,
        selectedItemColor: AppColors.blueprintLine,
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

import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppButtonStyles {
  static ButtonStyle primary({bool compact = true}) {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.38),
      disabledForegroundColor: Colors.white70,
      elevation: 0,
      minimumSize: Size(0, compact ? 42 : 48),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 20,
        vertical: compact ? 9 : 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: AppColors.blueprintLine.withValues(alpha: 0.55),
        ),
      ),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 15,
        letterSpacing: 0,
      ),
      shadowColor: AppColors.glow.withValues(alpha: 0.25),
    );
  }

  static ButtonStyle secondary({bool compact = true, Color? color}) {
    final buttonColor = color ?? AppColors.ink;
    return OutlinedButton.styleFrom(
      foregroundColor: buttonColor,
      side: BorderSide(color: buttonColor.withValues(alpha: 0.36)),
      minimumSize: Size(0, compact ? 40 : 46),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 8 : 11,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 14,
        letterSpacing: 0,
      ),
    );
  }

  static ButtonStyle text() {
    return TextButton.styleFrom(
      foregroundColor: AppColors.greenDark,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}

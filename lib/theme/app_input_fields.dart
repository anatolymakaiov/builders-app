import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

class AppInputFields {
  static InputDecoration decoration({
    String? label,
    String? hint,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      contentPadding: AppSpacing.field,
    );
  }

  static InputDecorationTheme theme() {
    OutlineInputBorder border(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface.withValues(alpha: 0.92),
      contentPadding: AppSpacing.field,
      labelStyle: const TextStyle(
        color: AppColors.muted,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: TextStyle(
        color: AppColors.muted.withValues(alpha: 0.74),
        fontWeight: FontWeight.w600,
      ),
      prefixIconColor: AppColors.ink,
      suffixIconColor: AppColors.ink,
      border: border(AppColors.blueprintLine.withValues(alpha: 0.28)),
      enabledBorder: border(AppColors.blueprintLine.withValues(alpha: 0.34)),
      focusedBorder: border(AppColors.blueprintLine, width: 1.4),
      errorBorder: border(AppColors.danger.withValues(alpha: 0.72)),
      focusedErrorBorder: border(AppColors.danger, width: 1.4),
    );
  }
}

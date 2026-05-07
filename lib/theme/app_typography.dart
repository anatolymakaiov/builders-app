import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTypography {
  static const title = TextStyle(
    color: Colors.white,
    fontSize: 28,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
  );

  static const sectionTitle = TextStyle(
    color: AppColors.ink,
    fontSize: 22,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
  );

  static const cardTitle = TextStyle(
    color: AppColors.ink,
    fontSize: 19,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
  );

  static const body = TextStyle(
    color: AppColors.ink,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
  );

  static const label = TextStyle(
    color: AppColors.muted,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const chip = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
  );
}

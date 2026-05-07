import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

class AppChip extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  final bool filled;

  const AppChip({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.filled = false,
  });

  factory AppChip.status(String label, {Color? color}) {
    return AppChip(
      label: label,
      color: color ?? AppColors.status(label),
      filled: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.greenDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: filled
            ? chipColor.withValues(alpha: 0.16)
            : AppColors.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: chipColor.withValues(alpha: 0.48),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: chipColor.withValues(alpha: 0.12),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: chipColor),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.chip.copyWith(color: chipColor),
            ),
          ),
        ],
      ),
    );
  }
}

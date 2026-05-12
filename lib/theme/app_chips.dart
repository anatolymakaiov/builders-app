import 'package:flutter/material.dart';

import 'app_blueprint.dart';
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

    return CustomPaint(
      painter: BlueprintDecorationPainter(
        fillColor: filled
            ? chipColor.withValues(alpha: 0.13)
            : AppColors.surface.withValues(alpha: 0.86),
        lineColor: chipColor,
        gridColor: chipColor,
        radius: 6,
        subtle: true,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: chipColor.withValues(alpha: 0.1),
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
      ),
    );
  }
}

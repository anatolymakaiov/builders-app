import 'package:flutter/material.dart';

import 'app_blueprint.dart';
import 'app_colors.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry padding;
  final bool blueprintCorners;
  final bool dimmed;
  final String texture;

  const AppCard({
    super.key,
    required this.child,
    this.margin,
    this.padding = const EdgeInsets.all(16),
    this.blueprintCorners = true,
    this.dimmed = false,
    this.texture = "assets/branding/texture_light_triangles.jpg",
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      decoration: BoxDecoration(
        color: dimmed ? AppColors.surfaceAlt : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(
                  image: AssetImage(texture),
                  fit: BoxFit.cover,
                  opacity: 0.48,
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: CustomPaint(
              painter: BlueprintDecorationPainter(
                fillColor: Colors.transparent,
                lineColor: AppColors.blueprintLine,
                gridColor: AppColors.blueprintLine,
                radius: 12,
                subtle: true,
              ),
            ),
          ),
          Padding(
            padding: padding,
            child: child,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_colors.dart';

class BlueprintCorners extends StatelessWidget {
  final Color color;
  final double size;

  const BlueprintCorners({
    super.key,
    this.color = AppColors.blueprintLine,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _BlueprintCornerPainter(color: color, size: size),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BlueprintCornerPainter extends CustomPainter {
  final Color color;
  final double size;

  const _BlueprintCornerPainter({
    required this.color,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.44)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    void corner(double x, double y, int sx, int sy) {
      canvas.drawLine(
        Offset(x, y + sy * size),
        Offset(x, y),
        paint,
      );
      canvas.drawLine(
        Offset(x, y),
        Offset(x + sx * size, y),
        paint,
      );
    }

    corner(0, 0, 1, 1);
    corner(canvasSize.width, 0, -1, 1);
    corner(0, canvasSize.height, 1, -1);
    corner(canvasSize.width, canvasSize.height, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _BlueprintCornerPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.size != size;
  }
}

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
          Padding(
            padding: padding,
            child: child,
          ),
          if (blueprintCorners)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: BlueprintCorners(
                  color: AppColors.blueprint.withValues(alpha: 0.72),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_theme.dart';

class StroykaBackground extends StatelessWidget {
  final Widget child;
  final String asset;

  const StroykaBackground({
    super.key,
    required this.child,
    this.asset = "assets/branding/bg_dark_workspace.jpg",
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.deep,
            image: DecorationImage(
              image: AssetImage(asset),
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.deep.withValues(alpha: 0.36),
                AppColors.navy.withValues(alpha: 0.72),
                AppColors.deep.withValues(alpha: 0.92),
              ],
            ),
          ),
        ),
        const _BlueprintGridOverlay(),
        child,
      ],
    );
  }
}

class _BlueprintGridOverlay extends StatelessWidget {
  const _BlueprintGridOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _BlueprintGridPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BlueprintGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = AppColors.blueprintLine.withValues(alpha: 0.035)
      ..strokeWidth = 0.7;
    final major = Paint()
      ..color = AppColors.blueprintLine.withValues(alpha: 0.07)
      ..strokeWidth = 0.8;

    const step = 24.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minor);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minor);
    }
    for (var x = 0.0; x < size.width; x += step * 4) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), major);
    }
    for (var y = 0.0; y < size.height; y += step * 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), major);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StroykaSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry borderRadius;
  final String texture;

  const StroykaSurface({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.texture = "assets/branding/texture_light_triangles.jpg",
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      texture: texture,
      child: child,
    );
  }
}

class StroykaScreenBody extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String texture;

  const StroykaScreenBody({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.texture = "assets/branding/texture_light_triangles.jpg",
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: padding,
      child: child,
    );
  }
}

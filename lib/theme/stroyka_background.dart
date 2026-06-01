import 'package:flutter/material.dart';

import 'app_theme.dart';

class StroykaBackground extends StatelessWidget {
  final Widget child;
  final String asset;

  const StroykaBackground({
    super.key,
    required this.child,
    this.asset = AppAssets.backgroundCranesYard,
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
        child,
      ],
    );
  }
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

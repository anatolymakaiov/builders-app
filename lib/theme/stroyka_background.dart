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
                AppColors.deep.withValues(alpha: 0.24),
                AppColors.navy.withValues(alpha: 0.66),
                AppColors.deep.withValues(alpha: 0.88),
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
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: borderRadius,
        image: DecorationImage(
          image: AssetImage(texture),
          fit: BoxFit.cover,
          opacity: 0.68,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
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
    return StroykaSurface(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: padding,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(18),
      ),
      texture: texture,
      child: child,
    );
  }
}

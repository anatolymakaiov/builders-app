import 'package:flutter/material.dart';

import '../theme/web_theme.dart';

class WebPanel extends StatelessWidget {
  const WebPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(WebSpacing.lg),
    this.margin = EdgeInsets.zero,
    this.elevated = false,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool elevated;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: clipBehavior,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: WebTheme.surface,
        borderRadius: BorderRadius.circular(WebRadii.panel),
        border: Border.all(color: WebTheme.border),
        boxShadow: elevated ? WebShadows.elevated : null,
      ),
      child: child,
    );
  }
}

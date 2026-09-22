import 'package:flutter/material.dart';

import '../theme/web_breakpoints.dart';
import '../theme/web_theme.dart';

class WebPageContainer extends StatelessWidget {
  const WebPageContainer({
    super.key,
    required this.child,
    this.padding,
    this.topPadding = WebSpacing.xl,
    this.bottomPadding = WebSpacing.xxl,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = WebBreakpoints.gutter(constraints.maxWidth);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: WebBreakpoints.desktopMaxWidth,
            ),
            child: Padding(
              padding: padding ??
                  EdgeInsets.fromLTRB(
                    gutter,
                    topPadding,
                    gutter,
                    bottomPadding,
                  ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

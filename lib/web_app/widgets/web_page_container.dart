import 'package:flutter/material.dart';

import '../theme/web_breakpoints.dart';
import '../theme/web_theme.dart';

class WebPageContainer extends StatelessWidget {
  const WebPageContainer({
    super.key,
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

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
                    WebSpacing.xl,
                    gutter,
                    WebSpacing.xxl,
                  ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/web_breakpoints.dart';
import '../theme/web_theme.dart';
import '../portrait/portrait_worker_presentation.dart';

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
    final portraitWorker = PortraitWorkerPresentation.enabled(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter =
            portraitWorker ? 12.0 : WebBreakpoints.gutter(constraints.maxWidth);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: portraitWorker
                  ? double.infinity
                  : WebBreakpoints.desktopMaxWidth,
            ),
            child: Padding(
              padding: padding ??
                  EdgeInsets.fromLTRB(
                    gutter,
                    portraitWorker ? 8 : topPadding,
                    gutter,
                    portraitWorker ? 8 : bottomPadding,
                  ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/web_breakpoints.dart';

class WebPageContainer extends StatelessWidget {
  const WebPageContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(32, 28, 32, 40),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: WebBreakpoints.desktopMaxWidth,
        ),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

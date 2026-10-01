import 'package:flutter/material.dart';

import '../theme/web_theme.dart';

/// Paints the full toolbar height; InputDecorator can paint a shorter outline
/// than its constrained parent on Flutter Web.
class WebToolbarField extends StatefulWidget {
  const WebToolbarField({super.key, required this.child});

  final Widget child;

  @override
  State<WebToolbarField> createState() => _WebToolbarFieldState();
}

class _WebToolbarFieldState extends State<WebToolbarField> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: WebToolbar.controlHeight,
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (value) => setState(() => focused = value),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: WebTheme.surface,
            borderRadius: BorderRadius.circular(WebRadii.input),
            border: Border.all(
              color: focused ? WebTheme.accent : WebTheme.border,
              width: focused ? 1.5 : 1,
            ),
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}

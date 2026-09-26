import 'package:flutter/material.dart';

/// Marks the Worker-only portrait subtree for compact Web presentation.
class PortraitWorkerPresentation extends InheritedWidget {
  const PortraitWorkerPresentation({super.key, required super.child});

  static bool enabled(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PortraitWorkerPresentation>() !=
      null;

  @override
  bool updateShouldNotify(PortraitWorkerPresentation oldWidget) => false;
}

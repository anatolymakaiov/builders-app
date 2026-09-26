import 'package:flutter/material.dart';

import 'portrait_worker_presentation.dart';

class PortraitEmployerPresentation extends InheritedWidget {
  const PortraitEmployerPresentation({super.key, required super.child});

  static bool enabled(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PortraitEmployerPresentation>() !=
      null;

  @override
  bool updateShouldNotify(PortraitEmployerPresentation oldWidget) => false;
}

bool isPortraitWebPresentation(BuildContext context) =>
    PortraitWorkerPresentation.enabled(context) ||
    PortraitEmployerPresentation.enabled(context);

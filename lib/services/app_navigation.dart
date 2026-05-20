import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class ShellNavigationCommand {
  final String? role;
  final int tabIndex;
  final int? employerProfileInitialTab;

  const ShellNavigationCommand({
    this.role,
    required this.tabIndex,
    this.employerProfileInitialTab,
  });
}

final ValueNotifier<ShellNavigationCommand?> shellNavigationCommand =
    ValueNotifier<ShellNavigationCommand?>(null);

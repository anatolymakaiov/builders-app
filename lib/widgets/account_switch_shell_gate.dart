import 'package:flutter/material.dart';

class AccountSwitchShellGate extends StatelessWidget {
  const AccountSwitchShellGate({
    super.key,
    required this.authenticatedUid,
    required this.switchTargetUid,
    required this.onShellQuiesced,
    required this.child,
  });

  final String? authenticatedUid;
  final String? switchTargetUid;
  final ValueChanged<String> onShellQuiesced;
  final Widget child;

  bool get _isSwitching =>
      switchTargetUid != null && switchTargetUid != authenticatedUid;

  @override
  Widget build(BuildContext context) {
    final targetUid = switchTargetUid;
    if (_isSwitching && targetUid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onShellQuiesced(targetUid);
      });
      return const Scaffold(
        key: ValueKey('account-switch-loading'),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return KeyedSubtree(
      key: const ValueKey('authenticated-shell'),
      child: child,
    );
  }
}

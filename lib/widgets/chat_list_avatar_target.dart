import 'package:flutter/material.dart';

class ChatListAvatarTarget extends StatelessWidget {
  const ChatListAvatarTarget({
    super.key,
    required this.onOpenProfile,
    required this.child,
  });

  final VoidCallback onOpenProfile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open profile',
      child: InkWell(
        onTap: onOpenProfile,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(child: child),
        ),
      ),
    );
  }
}

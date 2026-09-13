import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';

class WebProfilePage extends StatelessWidget {
  const WebProfilePage({
    super.key,
    required this.user,
    required this.role,
    required this.profile,
  });

  final User user;
  final String role;
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final displayName = (profile['companyName'] ??
            profile['name'] ??
            profile['displayName'] ??
            user.email ??
            'Profile')
        .toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: WebTheme.surface,
      ),
      body: WebPageContainer(
        child: WebPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(displayName,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                role,
                style: const TextStyle(
                  color: WebTheme.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Text(user.email ?? ''),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../pages/applications/web_applications_page.dart';
import '../pages/chats/web_chats_page.dart';
import '../pages/jobs/web_jobs_page.dart';
import '../pages/map/web_map_page.dart';
import '../pages/profile/web_profile_page.dart';
import '../theme/web_theme.dart';
import 'web_profile_menu.dart';
import 'web_top_navigation.dart';

class WebShell extends StatefulWidget {
  const WebShell({
    super.key,
    required this.user,
    required this.role,
    required this.profile,
  });

  final User user;
  final String role;
  final Map<String, dynamic> profile;

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  WebSection selected = WebSection.jobs;

  @override
  Widget build(BuildContext context) {
    final page = switch (selected) {
      WebSection.jobs => WebJobsPage(
          userId: widget.user.uid,
          role: widget.role,
        ),
      WebSection.map => const WebMapPage(),
      WebSection.applications => const WebApplicationsPage(),
      WebSection.chats => const WebChatsPage(),
    };

    return Scaffold(
      backgroundColor: WebTheme.page,
      body: Column(
        children: [
          WebTopNavigation(
            selected: selected,
            role: widget.role,
            avatar: WebProfileAvatar(profile: widget.profile),
            onSelected: (value) => setState(() => selected = value),
            onPostJob: () {},
            onProfile: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WebProfilePage(
                    user: widget.user,
                    role: widget.role,
                    profile: widget.profile,
                  ),
                ),
              );
            },
            onSignOut: () => FirebaseAuth.instance.signOut(),
          ),
          Expanded(child: page),
        ],
      ),
    );
  }
}

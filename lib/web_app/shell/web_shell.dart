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
  _WebProfileRoute? profileRoute;

  @override
  Widget build(BuildContext context) {
    final page = profileRoute == null
        ? switch (selected) {
            WebSection.jobs => WebJobsPage(
                userId: widget.user.uid,
                role: widget.role,
                onOpenProfile: _openProfile,
              ),
            WebSection.map => WebMapPage(
                userId: widget.user.uid,
                role: widget.role,
              ),
            WebSection.applications => WebApplicationsPage(
                userId: widget.user.uid,
                role: widget.role,
                onOpenProfile: _openProfile,
              ),
            WebSection.chats => WebChatsPage(
                userId: widget.user.uid,
                role: widget.role,
              ),
          }
        : WebProfilePage(
            user: widget.user,
            role: widget.role,
            profile: widget.profile,
            viewedUserId: profileRoute!.userId,
            viewedRole: profileRoute!.role,
            onClose: () => setState(() => profileRoute = null),
          );

    return Scaffold(
      backgroundColor: WebTheme.page,
      body: Column(
        children: [
          WebTopNavigation(
            selected: selected,
            role: widget.role,
            avatar: WebProfileAvatar(profile: widget.profile),
            onSelected: (value) => setState(() {
              selected = value;
              profileRoute = null;
            }),
            onPostJob: () {},
            onProfile: () => _openProfile(widget.user.uid, widget.role),
            onSignOut: () => FirebaseAuth.instance.signOut(),
          ),
          Expanded(child: page),
        ],
      ),
    );
  }

  void _openProfile(String userId, String role) {
    setState(() {
      profileRoute = _WebProfileRoute(userId: userId, role: role);
    });
  }
}

class _WebProfileRoute {
  const _WebProfileRoute({required this.userId, required this.role});

  final String userId;
  final String role;
}

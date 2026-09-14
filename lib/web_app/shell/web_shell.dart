import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../pages/applications/web_applications_page.dart';
import '../pages/chats/web_chats_page.dart';
import '../pages/jobs/web_jobs_page.dart';
import '../pages/jobs/web_post_job_page.dart';
import '../pages/map/web_map_page.dart';
import '../../services/application_status_utils.dart';
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
  String? initialChatId;
  _ApplicationsRoute? applicationsRoute;
  bool postingJob = false;

  @override
  Widget build(BuildContext context) {
    final page = postingJob
        ? WebPostJobPage(
            userId: widget.user.uid,
            onCancel: () => setState(() => postingJob = false),
            onDone: (_) => setState(() {
              postingJob = false;
              selected = WebSection.jobs;
            }),
            onOpenBilling: () => _openProfile(widget.user.uid, widget.role),
          )
        : profileRoute == null
            ? switch (selected) {
                WebSection.jobs => WebJobsPage(
                    userId: widget.user.uid,
                    role: widget.role,
                    onOpenProfile: _openProfile,
                    onViewApplications: _openApplications,
                  ),
                WebSection.map => WebMapPage(
                    userId: widget.user.uid,
                    role: widget.role,
                  ),
                WebSection.applications => WebApplicationsPage(
                    userId: widget.user.uid,
                    role: widget.role,
                    onOpenProfile: _openProfile,
                    onOpenChat: _openChat,
                    initialJobId: applicationsRoute?.jobId,
                    initialStatusFilter: applicationsRoute?.statusFilter,
                  ),
                WebSection.chats => WebChatsPage(
                    userId: widget.user.uid,
                    role: widget.role,
                    initialChatId: initialChatId,
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
              postingJob = false;
              if (value != WebSection.chats) initialChatId = null;
              if (value != WebSection.applications) applicationsRoute = null;
            }),
            onPostJob: _openPostJob,
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
      postingJob = false;
      profileRoute = _WebProfileRoute(userId: userId, role: role);
    });
  }

  void _openChat(String chatId) {
    setState(() {
      selected = WebSection.chats;
      profileRoute = null;
      postingJob = false;
      initialChatId = chatId;
    });
  }

  void _openPostJob() {
    setState(() {
      selected = WebSection.jobs;
      profileRoute = null;
      initialChatId = null;
      applicationsRoute = null;
      postingJob = true;
    });
  }

  void _openApplications(String jobId, {String? statusFilter}) {
    setState(() {
      selected = WebSection.applications;
      profileRoute = null;
      postingJob = false;
      initialChatId = null;
      applicationsRoute = _ApplicationsRoute(
        jobId: jobId,
        statusFilter: statusFilter ?? ApplicationStatusUtils.allFilter,
      );
    });
  }
}

class _WebProfileRoute {
  const _WebProfileRoute({required this.userId, required this.role});

  final String userId;
  final String role;
}

class _ApplicationsRoute {
  const _ApplicationsRoute({required this.jobId, required this.statusFilter});

  final String jobId;
  final String statusFilter;
}

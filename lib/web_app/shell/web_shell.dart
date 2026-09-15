import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../pages/account/web_account_page.dart';
import '../pages/account/web_notifications_page.dart';
import '../pages/account/web_saved_jobs_page.dart';
import '../pages/applications/web_applications_page.dart';
import '../pages/chats/web_chats_page.dart';
import '../pages/jobs/web_jobs_page.dart';
import '../pages/jobs/web_post_job_page.dart';
import '../pages/map/web_map_page.dart';
import '../../services/application_status_utils.dart';
import '../services/web_account_data_service.dart';
import '../services/web_data_state.dart';
import '../pages/profile/web_profile_page.dart';
import '../pages/profile/web_team_page.dart';
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
  final profileHistory = <_WebProfileRoute>[];
  String? initialChatId;
  _ApplicationsRoute? applicationsRoute;
  String? initialJobId;
  bool? initialJobOwnerMode;
  String? initialMapJobId;
  String? mapJobDetailId;
  int mapSavedJobsRefreshToken = 0;
  bool postingJob = false;
  _SecondaryRoute? secondaryRoute;
  late Stream<WebDataState<WebShellBadges>> badgesStream;

  @override
  void initState() {
    super.initState();
    badgesStream = WebAccountDataService().badges(
      uid: widget.user.uid,
      role: widget.role,
    );
  }

  @override
  void didUpdateWidget(covariant WebShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid ||
        oldWidget.role != widget.role) {
      badgesStream = WebAccountDataService().badges(
        uid: widget.user.uid,
        role: widget.role,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryPage = postingJob
        ? WebPostJobPage(
            userId: widget.user.uid,
            onCancel: () => setState(() => postingJob = false),
            onDone: (_) => setState(() {
              postingJob = false;
              selected = WebSection.jobs;
            }),
            onOpenBilling: () => _openAccount(WebAccountDestination.billing),
          )
        : profileRoute == null
            ? switch (selected) {
                WebSection.jobs => WebJobsPage(
                    userId: widget.user.uid,
                    role: widget.role,
                    initialJobId: initialJobId,
                    initialOwnerMode: initialJobOwnerMode,
                    onOpenProfile: _openProfile,
                    onPostJob: widget.role == 'employer' ? _openPostJob : null,
                    onOpenSubscriptions: widget.role == 'worker'
                        ? () => _openAccount(
                              WebAccountDestination.subscriptions,
                            )
                        : null,
                    onOpenChat: _openChat,
                    onShowOnMap: _openJobOnMap,
                    onViewApplications: _openApplications,
                  ),
                WebSection.map => WebMapPage(
                    userId: widget.user.uid,
                    role: widget.role,
                    initialJobId: initialMapJobId,
                    onOpenProfile: _openProfile,
                    onOpenJob: _openJobFromMap,
                    savedJobsRefreshToken: mapSavedJobsRefreshToken,
                  ),
                WebSection.applications => WebApplicationsPage(
                    userId: widget.user.uid,
                    role: widget.role,
                    onOpenProfile: _openProfile,
                    onOpenChat: _openChat,
                    initialJobId: applicationsRoute?.jobId,
                    initialApplicationId: applicationsRoute?.applicationId,
                    initialStatusFilter: applicationsRoute?.statusFilter,
                  ),
                WebSection.chats => WebChatsPage(
                    userId: widget.user.uid,
                    role: widget.role,
                    initialChatId: initialChatId,
                    onOpenProfile: _openProfile,
                    onOpenJob: (jobId) => _openJob(jobId),
                  ),
              }
            : profileRoute!.role == 'team'
                ? WebTeamPage(
                    teamId: profileRoute!.userId,
                    role: widget.role,
                    onBack: _closeProfile,
                    onProfile: _openProfile,
                    onChat: _openChat,
                  )
                : WebProfilePage(
                    user: widget.user,
                    role: widget.role,
                    profile: widget.profile,
                    viewedUserId: profileRoute!.userId,
                    viewedRole: profileRoute!.role,
                    onClose: _closeProfile,
                    onOpenChat: _openChat,
                    onOpenProfile: _openProfile,
                    onOpenJob: (jobId, ownerView) =>
                        _openJob(jobId, ownerMode: ownerView),
                    onAdminInbox: () =>
                        _openAccount(WebAccountDestination.adminInbox),
                  );
    final mapJobPage = mapJobDetailId == null
        ? null
        : WebJobsPage(
            userId: widget.user.uid,
            role: widget.role,
            initialJobId: mapJobDetailId,
            initialOwnerMode: false,
            onOpenProfile: _openProfile,
            onOpenSubscriptions: widget.role == 'worker'
                ? () => _openAccount(WebAccountDestination.subscriptions)
                : null,
            onOpenChat: _openChat,
            onShowOnMap: _returnToMapJob,
            onBackToMap: _closeMapJobDetail,
          );
    final secondaryPage =
        secondaryRoute == null ? null : _secondaryPage(secondaryRoute!);

    return Scaffold(
      backgroundColor: WebTheme.page,
      body: Column(
        children: [
          StreamBuilder<WebDataState<WebShellBadges>>(
            stream: badgesStream,
            builder: (context, snapshot) {
              final badges = snapshot.data?.data ?? const WebShellBadges();
              return WebTopNavigation(
                selected: mapJobPage == null ? selected : WebSection.jobs,
                role: widget.role,
                avatar: WebProfileAvatar(
                  profile: widget.profile,
                  role: widget.role,
                ),
                notificationCount: badges.notifications,
                chatCount: badges.chats,
                applicationCount: badges.applications,
                adminInboxCount: badges.adminInbox,
                onSelected: _selectSection,
                onPostJob: _openPostJob,
                onNotifications: _openNotifications,
                onAccountDestination: _openAccountValue,
                onProfile: () => _openProfile(widget.user.uid, widget.role),
                onSignOut: () => FirebaseAuth.instance.signOut(),
              );
            },
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Offstage(
                  offstage: secondaryPage != null || mapJobPage != null,
                  child: primaryPage,
                ),
                if (mapJobPage != null)
                  Offstage(
                    offstage: secondaryPage != null,
                    child: mapJobPage,
                  ),
                if (secondaryPage != null) secondaryPage,
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openProfile(String userId, String role) {
    setState(() {
      if (profileRoute != null) profileHistory.add(profileRoute!);
      secondaryRoute = null;
      postingJob = false;
      mapJobDetailId = null;
      profileRoute = _WebProfileRoute(userId: userId, role: role);
    });
  }

  void _closeProfile() => setState(() => profileRoute =
      profileHistory.isEmpty ? null : profileHistory.removeLast());

  void _openChat(String chatId) {
    setState(() {
      profileHistory.clear();
      selected = WebSection.chats;
      profileRoute = null;
      secondaryRoute = null;
      postingJob = false;
      initialChatId = chatId;
      initialMapJobId = null;
      mapJobDetailId = null;
    });
  }

  void _openJob(String jobId, {bool? ownerMode}) {
    setState(() {
      profileHistory.clear();
      selected = WebSection.jobs;
      initialJobId = jobId;
      initialJobOwnerMode = ownerMode;
      initialMapJobId = null;
      mapJobDetailId = null;
      secondaryRoute = null;
      profileRoute = null;
      postingJob = false;
    });
  }

  void _openJobOnMap(String jobId) {
    setState(() {
      profileHistory.clear();
      selected = WebSection.map;
      initialMapJobId = jobId;
      initialJobId = null;
      initialJobOwnerMode = null;
      secondaryRoute = null;
      profileRoute = null;
      postingJob = false;
      mapJobDetailId = null;
    });
  }

  void _openJobFromMap(String jobId) {
    setState(() {
      mapJobDetailId = jobId;
      secondaryRoute = null;
      profileRoute = null;
      postingJob = false;
    });
  }

  void _closeMapJobDetail() {
    setState(() {
      mapJobDetailId = null;
      mapSavedJobsRefreshToken++;
    });
  }

  void _returnToMapJob(String jobId) {
    setState(() {
      initialMapJobId = jobId;
      mapJobDetailId = null;
      mapSavedJobsRefreshToken++;
    });
  }

  void _openPostJob() {
    setState(() {
      selected = WebSection.jobs;
      profileRoute = null;
      secondaryRoute = null;
      initialChatId = null;
      applicationsRoute = null;
      initialJobId = null;
      initialJobOwnerMode = null;
      initialMapJobId = null;
      postingJob = true;
      mapJobDetailId = null;
    });
  }

  void _openApplications(
    String jobId, {
    String? applicationId,
    String? statusFilter,
  }) {
    setState(() {
      profileHistory.clear();
      selected = WebSection.applications;
      profileRoute = null;
      secondaryRoute = null;
      postingJob = false;
      initialChatId = null;
      initialJobId = null;
      initialJobOwnerMode = null;
      initialMapJobId = null;
      applicationsRoute = _ApplicationsRoute(
        jobId: jobId,
        applicationId: applicationId,
        statusFilter: statusFilter ?? ApplicationStatusUtils.allFilter,
      );
      mapJobDetailId = null;
    });
  }

  void _selectSection(WebSection value) {
    setState(() {
      profileHistory.clear();
      selected = value;
      profileRoute = null;
      secondaryRoute = null;
      postingJob = false;
      if (value != WebSection.chats) initialChatId = null;
      if (value != WebSection.applications) applicationsRoute = null;
      if (value != WebSection.jobs) initialJobId = null;
      if (value != WebSection.jobs) initialJobOwnerMode = null;
      if (value != WebSection.map) initialMapJobId = null;
      mapJobDetailId = null;
    });
  }

  Widget _secondaryPage(_SecondaryRoute route) {
    return switch (route.kind) {
      _SecondaryKind.notifications => WebNotificationsPage(
          userId: widget.user.uid,
          role: widget.role,
          onClose: _closeSecondary,
          onRoute: _routeNotification,
        ),
      _SecondaryKind.savedJobs => WebSavedJobsPage(
          userId: widget.user.uid,
          onClose: _closeSecondary,
          onOpenProfile: _openProfile,
        ),
      _SecondaryKind.account => WebAccountPage(
          user: widget.user,
          role: widget.role,
          profile: widget.profile,
          initialDestination:
              route.destination ?? WebAccountDestination.account,
          onClose: _closeSecondary,
          onSignedOut: () => FirebaseAuth.instance.signOut(),
        ),
    };
  }

  void _closeSecondary() {
    setState(() => secondaryRoute = null);
  }

  void _openNotifications() {
    setState(() {
      profileHistory.clear();
      secondaryRoute = const _SecondaryRoute(_SecondaryKind.notifications);
      profileRoute = null;
      postingJob = false;
    });
  }

  void _openAccountValue(String value) {
    if (value == 'savedJobs') {
      setState(() {
        profileHistory.clear();
        secondaryRoute = const _SecondaryRoute(_SecondaryKind.savedJobs);
        profileRoute = null;
        postingJob = false;
      });
      return;
    }
    final destination = WebAccountDestination.values.firstWhere(
      (item) => item.name == value,
      orElse: () => WebAccountDestination.account,
    );
    _openAccount(destination);
  }

  void _openAccount(WebAccountDestination destination) {
    setState(() {
      profileHistory.clear();
      secondaryRoute = _SecondaryRoute(
        _SecondaryKind.account,
        destination: destination,
      );
      profileRoute = null;
      postingJob = false;
    });
  }

  void _routeNotification(WebNotificationItem notification) {
    final data = notification.data;
    final targetType = _targetTypeFor(data);
    final targetId = _cleanId(data['targetId']);
    final chatId = _cleanId(data['chatId'] ?? targetId);
    final jobId = _cleanId(data['relatedJobId'] ?? data['jobId'] ?? targetId);
    final applicationId = _cleanId(
      data['relatedApplicationId'] ?? data['applicationId'] ?? targetId,
    );
    if (targetType == 'chat' && chatId != null) {
      _openChat(chatId);
      return;
    }
    if ((targetType == 'application' || targetType == 'offer') &&
        applicationId != null) {
      _openApplications(
        jobId ?? '',
        applicationId: applicationId,
        statusFilter: ApplicationStatusUtils.allFilter,
      );
      return;
    }
    if ((targetType == 'job' || targetType == 'inactive_job') &&
        jobId != null) {
      setState(() {
        selected = WebSection.jobs;
        initialJobId = jobId;
        initialJobOwnerMode = null;
        secondaryRoute = null;
        profileRoute = null;
        postingJob = false;
      });
      return;
    }
    if (targetType == 'billing' || targetType == 'payment') {
      _openAccount(WebAccountDestination.billing);
      return;
    }
    if (targetType == 'admin_message' ||
        targetType == 'support_request' ||
        targetType == 'report') {
      _openAccount(WebAccountDestination.adminInbox);
      return;
    }
  }

  String _targetTypeFor(Map<String, dynamic> data) {
    final explicit = _cleanId(data['targetType']);
    if (explicit != null) return explicit;
    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    if (type == 'message' || data['chatId'] != null) return 'chat';
    if (type == 'billing' || data['relatedPaymentRequestId'] != null) {
      return 'billing';
    }
    if (type == 'report' || data['relatedReportId'] != null) return 'report';
    if (type == 'support' || data['relatedSupportRequestId'] != null) {
      return 'support_request';
    }
    if (type == 'admin_message') return 'admin_message';
    if (type.contains('offer') || type.startsWith('work_start')) return 'offer';
    if (type == 'application' || type == 'application_status') {
      return 'application';
    }
    if (type == 'job_alert' ||
        type == 'job_status' ||
        type == 'package_approval') {
      return 'job';
    }
    return 'notification';
  }

  String? _cleanId(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return null;
    return text;
  }
}

class _WebProfileRoute {
  const _WebProfileRoute({required this.userId, required this.role});

  final String userId;
  final String role;
}

class _ApplicationsRoute {
  const _ApplicationsRoute({
    required this.jobId,
    required this.statusFilter,
    this.applicationId,
  });

  final String jobId;
  final String statusFilter;
  final String? applicationId;
}

enum _SecondaryKind { notifications, savedJobs, account }

class _SecondaryRoute {
  const _SecondaryRoute(this.kind, {this.destination});

  final _SecondaryKind kind;
  final WebAccountDestination? destination;
}

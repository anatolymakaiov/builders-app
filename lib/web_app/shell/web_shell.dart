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
  int jobsNavigationRequestId = 0;
  int jobsRefreshRequestId = 0;
  int mapNavigationRequestId = 0;
  int applicationsNavigationRequestId = 0;
  int chatsNavigationRequestId = 0;
  _JobReturnTarget? jobReturnTarget;
  bool profileCoveredByJob = false;
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
    final workspaces = <Widget>[
      WebJobsPage(
        key: ValueKey('web-jobs:${widget.user.uid}:${widget.role}'),
        userId: widget.user.uid,
        role: widget.role,
        initialJobId: initialJobId,
        initialOwnerMode: initialJobOwnerMode,
        navigationRequestId: jobsNavigationRequestId,
        refreshRequestId: jobsRefreshRequestId,
        backLabel: jobReturnTarget?.label ?? 'Back',
        onBackToMap: jobReturnTarget == null ? null : _closeTargetedJob,
        onOpenProfile: _openProfile,
        onPostJob: widget.role == 'employer' ? _openPostJob : null,
        onOpenSubscriptions: widget.role == 'worker'
            ? () => _openAccount(WebAccountDestination.subscriptions)
            : null,
        onOpenChat: _openChat,
        onShowOnMap: _openJobOnMap,
        onViewApplications: _openApplications,
      ),
      WebMapPage(
        key: ValueKey('web-map:${widget.user.uid}:${widget.role}'),
        userId: widget.user.uid,
        role: widget.role,
        initialJobId: initialMapJobId,
        navigationRequestId: mapNavigationRequestId,
        onOpenProfile: _openProfile,
        onOpenJob: _openJobFromMap,
        savedJobsRefreshToken: mapSavedJobsRefreshToken,
      ),
      WebApplicationsPage(
        key: ValueKey('web-applications:${widget.user.uid}:${widget.role}'),
        userId: widget.user.uid,
        role: widget.role,
        onOpenProfile: _openProfile,
        onOpenChat: _openChat,
        onOpenJob: _openJobFromApplications,
        initialJobId: applicationsRoute?.jobId,
        initialApplicationId: applicationsRoute?.applicationId,
        initialStatusFilter: applicationsRoute?.statusFilter,
        navigationRequestId: applicationsNavigationRequestId,
      ),
      WebChatsPage(
        key: ValueKey('web-chats:${widget.user.uid}:${widget.role}'),
        userId: widget.user.uid,
        role: widget.role,
        initialChatId: initialChatId,
        navigationRequestId: chatsNavigationRequestId,
        onOpenProfile: _openProfile,
        onOpenJob: _openJobFromChats,
      ),
    ];
    final profilePage = _profileStack();
    final postJobPage = postingJob
        ? WebPostJobPage(
            userId: widget.user.uid,
            onCancel: () => setState(() => postingJob = false),
            onDone: (_) => setState(() {
              postingJob = false;
              selected = WebSection.jobs;
              jobsRefreshRequestId++;
            }),
            onOpenBilling: () => _openAccount(WebAccountDestination.billing),
          )
        : null;
    final secondaryPage =
        secondaryRoute == null ? null : _secondaryPage(secondaryRoute!);
    final profileVisible = profilePage != null && !profileCoveredByJob;

    return Scaffold(
      backgroundColor: WebTheme.page,
      body: Column(
        children: [
          StreamBuilder<WebDataState<WebShellBadges>>(
            stream: badgesStream,
            builder: (context, snapshot) {
              final badges = snapshot.data?.data ?? const WebShellBadges();
              return WebTopNavigation(
                selected: selected,
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
                  offstage: secondaryPage != null ||
                      postJobPage != null ||
                      profileVisible,
                  child: IndexedStack(
                    index: selected.index,
                    sizing: StackFit.expand,
                    children: workspaces,
                  ),
                ),
                if (profilePage != null)
                  Offstage(
                    offstage: secondaryPage != null ||
                        postJobPage != null ||
                        !profileVisible,
                    child: profilePage,
                  ),
                if (postJobPage != null)
                  Offstage(
                    offstage: secondaryPage != null,
                    child: postJobPage,
                  ),
                if (secondaryPage != null) secondaryPage,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _profileStack() {
    final current = profileRoute;
    if (current == null) return null;
    final routes = [...profileHistory, current];
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final route in routes)
          Offstage(
            key: ObjectKey(route),
            offstage: !identical(route, current),
            child: _profilePage(route),
          ),
      ],
    );
  }

  Widget _profilePage(_WebProfileRoute route) {
    if (route.role == 'team') {
      return WebTeamPage(
        teamId: route.userId,
        role: widget.role,
        onBack: _closeProfile,
        onProfile: _openProfile,
        onChat: _openChat,
      );
    }
    return WebProfilePage(
      user: widget.user,
      role: widget.role,
      profile: widget.profile,
      viewedUserId: route.userId,
      viewedRole: route.role,
      onClose: _closeProfile,
      onOpenChat: _openChat,
      onOpenProfile: _openProfile,
      onOpenJob: _openJobFromProfile,
      onAdminInbox: () => _openAccount(WebAccountDestination.adminInbox),
    );
  }

  void _openProfile(String userId, String role) {
    setState(() {
      if (profileRoute != null) profileHistory.add(profileRoute!);
      secondaryRoute = null;
      postingJob = false;
      jobReturnTarget = null;
      profileCoveredByJob = false;
      profileRoute = _WebProfileRoute(userId: userId, role: role);
    });
  }

  void _closeProfile() => setState(() {
        profileCoveredByJob = false;
        profileRoute =
            profileHistory.isEmpty ? null : profileHistory.removeLast();
      });

  void _openChat(String chatId) {
    setState(() {
      profileHistory.clear();
      selected = WebSection.chats;
      profileRoute = null;
      profileCoveredByJob = false;
      jobReturnTarget = null;
      secondaryRoute = null;
      postingJob = false;
      initialChatId = chatId;
      chatsNavigationRequestId++;
    });
  }

  void _openJob(
    String jobId, {
    bool? ownerMode,
    _JobReturnTarget? returnTarget,
    bool preserveProfile = false,
  }) {
    setState(() {
      selected = WebSection.jobs;
      initialJobId = jobId;
      initialJobOwnerMode = ownerMode;
      jobsNavigationRequestId++;
      jobReturnTarget = returnTarget;
      profileCoveredByJob = preserveProfile;
      secondaryRoute = null;
      postingJob = false;
      if (!preserveProfile) {
        profileHistory.clear();
        profileRoute = null;
      }
    });
  }

  void _openJobOnMap(String jobId) {
    setState(() {
      profileHistory.clear();
      selected = WebSection.map;
      initialMapJobId = jobId;
      mapNavigationRequestId++;
      jobReturnTarget = null;
      profileCoveredByJob = false;
      secondaryRoute = null;
      profileRoute = null;
      postingJob = false;
    });
  }

  void _openJobFromMap(String jobId) => _openJob(
        jobId,
        ownerMode: false,
        returnTarget: _JobReturnTarget.map,
      );

  void _openJobFromApplications(String jobId) => _openJob(
        jobId,
        returnTarget: _JobReturnTarget.applications,
      );

  void _openJobFromChats(String jobId) => _openJob(
        jobId,
        returnTarget: _JobReturnTarget.chats,
      );

  void _openJobFromProfile(String jobId, bool ownerView) => _openJob(
        jobId,
        ownerMode: ownerView,
        returnTarget: _JobReturnTarget.profile,
        preserveProfile: true,
      );

  void _closeTargetedJob() {
    final target = jobReturnTarget;
    if (target == null) return;
    setState(() {
      jobReturnTarget = null;
      if (target == _JobReturnTarget.profile) {
        profileCoveredByJob = false;
      } else {
        selected = target.section!;
      }
      if (target == _JobReturnTarget.map) mapSavedJobsRefreshToken++;
    });
  }

  void _openPostJob() {
    setState(() {
      selected = WebSection.jobs;
      profileRoute = null;
      profileHistory.clear();
      profileCoveredByJob = false;
      jobReturnTarget = null;
      secondaryRoute = null;
      postingJob = true;
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
      profileCoveredByJob = false;
      jobReturnTarget = null;
      secondaryRoute = null;
      postingJob = false;
      applicationsRoute = _ApplicationsRoute(
        jobId: jobId,
        applicationId: applicationId,
        statusFilter: statusFilter ?? ApplicationStatusUtils.allFilter,
      );
      applicationsNavigationRequestId++;
    });
  }

  void _selectSection(WebSection value) {
    setState(() {
      profileHistory.clear();
      selected = value;
      profileRoute = null;
      profileCoveredByJob = false;
      jobReturnTarget = null;
      secondaryRoute = null;
      postingJob = false;
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
      secondaryRoute = const _SecondaryRoute(_SecondaryKind.notifications);
    });
  }

  void _openAccountValue(String value) {
    if (value == 'savedJobs') {
      setState(() {
        secondaryRoute = const _SecondaryRoute(_SecondaryKind.savedJobs);
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
      secondaryRoute = _SecondaryRoute(
        _SecondaryKind.account,
        destination: destination,
      );
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
      _openJob(jobId);
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

enum _JobReturnTarget {
  map('Back to Jobs Map', WebSection.map),
  applications('Back to Applications', WebSection.applications),
  chats('Back to Chats', WebSection.chats),
  profile('Back to profile', null);

  const _JobReturnTarget(this.label, this.section);

  final String label;
  final WebSection? section;
}

class _SecondaryRoute {
  const _SecondaryRoute(this.kind, {this.destination});

  final _SecondaryKind kind;
  final WebAccountDestination? destination;
}

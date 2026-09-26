import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../pages/account/web_account_page.dart';
import '../pages/account/web_notifications_page.dart';
import '../pages/applications/web_applications_page.dart';
import '../pages/chats/web_chats_page.dart';
import '../pages/jobs/web_jobs_page.dart';
import '../pages/jobs/web_post_job_page.dart';
import '../pages/map/web_map_page.dart';
import '../pages/profile/web_admin_profile_page.dart';
import '../pages/profile/web_profile_page.dart';
import '../pages/profile/web_team_page.dart';
import '../services/web_account_data_service.dart';
import '../services/web_data_state.dart';
import '../theme/web_theme.dart';
import 'portrait_web_navigation.dart';
import 'portrait_web_section.dart';

enum _PortraitOverlay { notifications, account, postJob }

class PortraitWebShell extends StatefulWidget {
  const PortraitWebShell({
    super.key,
    required this.user,
    required this.role,
    required this.profile,
  });

  final User user;
  final String role;
  final Map<String, dynamic> profile;

  @override
  State<PortraitWebShell> createState() => _PortraitWebShellState();
}

class _PortraitWebShellState extends State<PortraitWebShell> {
  PortraitWebSection selected = PortraitWebSection.jobs;
  final visited = <PortraitWebSection>{PortraitWebSection.jobs};
  _PortraitOverlay? overlay;
  WebAccountDestination accountDestination = WebAccountDestination.account;
  late Map<String, dynamic> liveProfile;
  late Stream<WebDataState<WebShellBadges>> badgesStream;
  String? viewedProfileId;
  String? viewedProfileRole;
  final profileHistory = <({String? id, String? role})>[];
  PortraitWebSection profileReturn = PortraitWebSection.jobs;
  String? jobId;
  bool? jobOwnerMode;
  PortraitWebSection? jobReturnSection;
  String? jobReturnProfileId;
  String? jobReturnProfileRole;
  String? mapJobId;
  String? applicationJobId;
  String? applicationId;
  String? applicationStatusFilter;
  String? chatId;
  int jobsRequest = 0;
  int jobsRefresh = 0;
  int mapRequest = 0;
  int applicationsRequest = 0;
  int chatsRequest = 0;

  @override
  void initState() {
    super.initState();
    liveProfile = Map<String, dynamic>.from(widget.profile);
    badgesStream = WebAccountDataService().badges(
      uid: widget.user.uid,
      role: widget.role,
    );
  }

  @override
  void didUpdateWidget(covariant PortraitWebShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid ||
        oldWidget.role != widget.role) {
      selected = PortraitWebSection.jobs;
      visited
        ..clear()
        ..add(PortraitWebSection.jobs);
      overlay = null;
      viewedProfileId = null;
      viewedProfileRole = null;
      profileHistory.clear();
      jobId = null;
      jobReturnSection = null;
      mapJobId = null;
      applicationJobId = null;
      chatId = null;
      badgesStream = WebAccountDataService().badges(
        uid: widget.user.uid,
        role: widget.role,
      );
    }
    if (oldWidget.profile != widget.profile) {
      liveProfile = Map<String, dynamic>.from(widget.profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WebDataState<WebShellBadges>>(
      stream: badgesStream,
      builder: (context, snapshot) {
        final badges = snapshot.data?.data ?? const WebShellBadges();
        return Scaffold(
          key: const ValueKey('portrait-web-root'),
          backgroundColor: WebTheme.page,
          appBar: AppBar(
            backgroundColor: WebTheme.deep,
            foregroundColor: Colors.white,
            title: Text(overlay == null ? 'STROYKA' : _title),
            leading: overlay != null || viewedProfileId != null
                ? IconButton(
                    tooltip: 'Back',
                    onPressed: overlay != null ? _closeOverlay : _closeProfile,
                    icon: const Icon(Icons.arrow_back),
                  )
                : null,
            automaticallyImplyLeading: false,
            actions: [
              if (widget.role == 'employer' &&
                  selected == PortraitWebSection.jobs &&
                  overlay == null)
                IconButton(
                  tooltip: 'Post a job',
                  onPressed: _openPostJob,
                  icon: const Icon(Icons.add),
                ),
              IconButton(
                tooltip: 'Notifications',
                onPressed: _openNotifications,
                icon: Badge(
                  isLabelVisible: badges.notifications > 0,
                  label: Text('${badges.notifications}'),
                  child: const Icon(Icons.notifications_none),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Account menu',
                icon: const Icon(Icons.more_vert),
                onSelected: _selectMenuAction,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'account', child: Text('My Account')),
                  if (widget.role == 'employer')
                    const PopupMenuItem(
                        value: 'billing', child: Text('Billing')),
                  if (widget.role == 'worker')
                    const PopupMenuItem(
                        value: 'subscriptions',
                        child: Text('Job Subscriptions')),
                  const PopupMenuItem(value: 'support', child: Text('Support')),
                  const PopupMenuItem(
                      value: 'signOut', child: Text('Sign out')),
                ],
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: overlay == null
                ? IndexedStack(
                    index: selected.index,
                    children: [
                      for (final section in PortraitWebSection.values)
                        visited.contains(section)
                            ? _buildSection(section)
                            : const SizedBox.shrink(),
                    ],
                  )
                : _buildOverlay(),
          ),
          bottomNavigationBar: overlay == null
              ? SafeArea(
                  top: false,
                  child: PortraitWebNavigation(
                    selected: selected,
                    onSelected: _selectSection,
                    applicationCount: badges.applications,
                    chatCount: badges.chats,
                  ),
                )
              : null,
        );
      },
    );
  }

  String get _title => switch (overlay) {
        _PortraitOverlay.notifications => 'Notifications',
        _PortraitOverlay.account => accountDestination.label,
        _PortraitOverlay.postJob => 'Post a job',
        null => selected.label,
      };

  Widget _buildSection(PortraitWebSection section) => switch (section) {
        PortraitWebSection.jobs => WebJobsPage(
            key: ValueKey('portrait-jobs:${widget.user.uid}'),
            userId: widget.user.uid,
            role: widget.role,
            initialJobId: jobId,
            initialOwnerMode: jobOwnerMode,
            navigationRequestId: jobsRequest,
            refreshRequestId: jobsRefresh,
            onBackToMap: jobReturnSection == null ? null : _closeTargetedJob,
            backLabel: jobReturnSection == null
                ? 'Back'
                : 'Back to ${jobReturnSection!.label}',
            onOpenProfile: _openProfile,
            onPostJob: widget.role == 'employer' ? _openPostJob : null,
            onOpenSubscriptions: widget.role == 'worker'
                ? () => _openAccount(WebAccountDestination.subscriptions)
                : null,
            onOpenChat: _openChat,
            onShowOnMap: _openJobOnMap,
            onViewApplications: _openApplications,
          ),
        PortraitWebSection.map => WebMapPage(
            key: ValueKey('portrait-map:${widget.user.uid}'),
            userId: widget.user.uid,
            role: widget.role,
            initialJobId: mapJobId,
            navigationRequestId: mapRequest,
            onOpenProfile: _openProfile,
            onOpenJob: (id) => _openJob(id, ownerMode: false),
          ),
        PortraitWebSection.applications => WebApplicationsPage(
            key: ValueKey('portrait-applications:${widget.user.uid}'),
            userId: widget.user.uid,
            role: widget.role,
            initialJobId: applicationJobId,
            initialApplicationId: applicationId,
            initialStatusFilter: applicationStatusFilter,
            navigationRequestId: applicationsRequest,
            onOpenProfile: _openProfile,
            onOpenChat: _openChat,
            onOpenJob: _openJob,
          ),
        PortraitWebSection.chats => WebChatsPage(
            key: ValueKey('portrait-chats:${widget.user.uid}'),
            userId: widget.user.uid,
            role: widget.role,
            initialChatId: chatId,
            navigationRequestId: chatsRequest,
            onOpenProfile: _openProfile,
            onOpenJob: _openJob,
          ),
        PortraitWebSection.profile => _buildProfile(),
      };

  Widget _buildProfile() {
    final profileId = viewedProfileId ?? widget.user.uid;
    final role = viewedProfileRole ?? widget.role;
    if (role == 'team') {
      return WebTeamPage(
        key: ValueKey('portrait-team:$profileId'),
        teamId: profileId,
        role: widget.role,
        onBack: _closeProfile,
        onProfile: _openProfile,
        onChat: _openChat,
      );
    }
    if (profileId == widget.user.uid && role == 'admin') {
      return WebAdminProfilePage(
        key: ValueKey('portrait-admin:$profileId'),
        uid: profileId,
        profile: liveProfile,
        onClose: _closeProfile,
        onOpenProfile: _openProfile,
      );
    }
    return WebProfilePage(
      key: ValueKey('portrait-profile:$profileId:$role'),
      user: widget.user,
      role: widget.role,
      profile: liveProfile,
      viewedUserId: profileId,
      viewedRole: role,
      onClose: _closeProfile,
      onOpenChat: _openChat,
      onOpenProfile: _openProfile,
      onOpenJob: (id, ownerView) => _openJob(id, ownerMode: ownerView),
      onAdminInbox: () => _openAccount(WebAccountDestination.adminInbox),
      onOwnProfileChanged: profileId == widget.user.uid
          ? (updates) =>
              setState(() => liveProfile = {...liveProfile, ...updates})
          : null,
    );
  }

  Widget _buildOverlay() => switch (overlay!) {
        _PortraitOverlay.notifications => WebNotificationsPage(
            userId: widget.user.uid,
            role: widget.role,
            onClose: _closeOverlay,
            onRoute: _routeNotification,
          ),
        _PortraitOverlay.account => WebAccountPage(
            user: widget.user,
            role: widget.role,
            profile: liveProfile,
            initialDestination: accountDestination,
            onClose: _closeOverlay,
            onSignedOut: () => FirebaseAuth.instance.signOut(),
          ),
        _PortraitOverlay.postJob => WebPostJobPage(
            userId: widget.user.uid,
            onCancel: _closeOverlay,
            onDone: (_) => setState(() {
              overlay = null;
              jobsRefresh++;
              _activate(PortraitWebSection.jobs);
            }),
            onOpenBilling: () => _openAccount(WebAccountDestination.billing),
          ),
      };

  void _activate(PortraitWebSection section) {
    selected = section;
    visited.add(section);
  }

  void _selectSection(PortraitWebSection section) => setState(() {
        if (section == PortraitWebSection.profile &&
            selected != PortraitWebSection.profile) {
          profileReturn = selected;
        }
        overlay = null;
        jobReturnSection = null;
        viewedProfileId = null;
        viewedProfileRole = null;
        profileHistory.clear();
        _activate(section);
      });

  void _openProfile(String id, String role) => setState(() {
        if (selected == PortraitWebSection.profile) {
          profileHistory.add((id: viewedProfileId, role: viewedProfileRole));
        } else {
          profileHistory.clear();
          profileReturn = selected;
        }
        viewedProfileId = id == widget.user.uid ? null : id;
        viewedProfileRole = id == widget.user.uid ? null : role;
        overlay = null;
        _activate(PortraitWebSection.profile);
      });

  void _closeProfile() => setState(() {
        if (profileHistory.isNotEmpty) {
          final previous = profileHistory.removeLast();
          viewedProfileId = previous.id;
          viewedProfileRole = previous.role;
          return;
        }
        viewedProfileId = null;
        viewedProfileRole = null;
        _activate(profileReturn == PortraitWebSection.profile
            ? PortraitWebSection.jobs
            : profileReturn);
      });

  void _openJob(String id, {bool? ownerMode}) => setState(() {
        jobReturnSection =
            selected == PortraitWebSection.jobs ? null : selected;
        jobReturnProfileId =
            selected == PortraitWebSection.profile ? viewedProfileId : null;
        jobReturnProfileRole =
            selected == PortraitWebSection.profile ? viewedProfileRole : null;
        jobId = id;
        jobOwnerMode = ownerMode;
        jobsRequest++;
        overlay = null;
        viewedProfileId = null;
        profileHistory.clear();
        _activate(PortraitWebSection.jobs);
      });

  void _closeTargetedJob() => setState(() {
        final destination = jobReturnSection;
        jobReturnSection = null;
        if (destination == null) return;
        if (destination == PortraitWebSection.profile) {
          viewedProfileId = jobReturnProfileId;
          viewedProfileRole = jobReturnProfileRole;
        }
        jobReturnProfileId = null;
        jobReturnProfileRole = null;
        _activate(destination);
      });

  void _openJobOnMap(String id) => setState(() {
        mapJobId = id;
        mapRequest++;
        overlay = null;
        _activate(PortraitWebSection.map);
      });

  void _openApplications(String id,
          {String? statusFilter, String? selectedApplicationId}) =>
      setState(() {
        applicationJobId = id;
        applicationId = selectedApplicationId;
        applicationStatusFilter = statusFilter;
        applicationsRequest++;
        overlay = null;
        _activate(PortraitWebSection.applications);
      });

  void _openChat(String id) => setState(() {
        chatId = id;
        chatsRequest++;
        overlay = null;
        _activate(PortraitWebSection.chats);
      });

  void _openPostJob() => setState(() => overlay = _PortraitOverlay.postJob);
  void _openNotifications() =>
      setState(() => overlay = _PortraitOverlay.notifications);
  void _openAccount(WebAccountDestination destination) => setState(() {
        accountDestination = destination;
        overlay = _PortraitOverlay.account;
      });
  void _closeOverlay() => setState(() => overlay = null);

  void _selectMenuAction(String action) {
    if (action == 'signOut') {
      FirebaseAuth.instance.signOut();
      return;
    }
    final destination = WebAccountDestination.values.firstWhere(
      (item) => item.name == action,
      orElse: () => WebAccountDestination.account,
    );
    _openAccount(destination);
  }

  void _routeNotification(WebNotificationItem notification) {
    final data = notification.data;
    final type =
        (data['targetType'] ?? data['type'] ?? '').toString().toLowerCase();
    final targetId = _cleanId(data['targetId']);
    final chatTarget = _cleanId(data['chatId']) ?? targetId;
    final jobTarget = _cleanId(data['relatedJobId'] ?? data['jobId']);
    final applicationTarget = _cleanId(
          data['relatedApplicationId'] ?? data['applicationId'],
        ) ??
        targetId;
    if ((type == 'chat' || type == 'message') && chatTarget != null) {
      _openChat(chatTarget);
    } else if ([
          'job',
          'job_status',
          'job_alert',
          'inactive_job',
          'package_approval'
        ].contains(type) &&
        (jobTarget ?? targetId) != null) {
      _openJob((jobTarget ?? targetId)!);
    } else if (type == 'billing' || type == 'payment') {
      _openAccount(WebAccountDestination.billing);
    } else if (type == 'application' ||
        type == 'application_status' ||
        type == 'offer' ||
        type.contains('offer') ||
        type.startsWith('work_start')) {
      _openApplications(jobTarget ?? '',
          selectedApplicationId: applicationTarget);
    } else if (['admin_message', 'support_request', 'report'].contains(type)) {
      _openAccount(WebAccountDestination.adminInbox);
    }
  }

  String? _cleanId(dynamic value) {
    final id = value?.toString().trim() ?? '';
    return id.isEmpty || id == 'null' ? null : id;
  }
}

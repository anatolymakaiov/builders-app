import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/job.dart';
import '../../services/moderation_hold_service.dart';
import '../pages/jobs/web_job_details_panel.dart';
import '../pages/jobs/web_worker_vacancy_card.dart';
import '../pages/profile/web_admin_profile_page.dart';
import '../pages/profile/web_worker_reviews.dart';
import '../services/web_admin_profile_service.dart';
import '../services/web_profile_data_service.dart';
import '../theme/web_theme.dart';
import '../widgets/web_remote_image.dart';
import 'admin_analytics_service.dart';
import 'admin_search_service.dart';

enum AdminWorkspace { overview, requests, search, view }

bool usesDedicatedAdminWebShell(String role) => role == 'admin';

enum AdminRequestTab { support, approvals, billing, inbox }

class AdminWebShell extends StatefulWidget {
  const AdminWebShell({super.key, required this.user, required this.profile});

  final User user;
  final Map<String, dynamic> profile;

  @override
  State<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<AdminWebShell> {
  final admin = WebAdminProfileService();
  final analytics = AdminAnalyticsService();
  final searchService = AdminSearchService();
  late Future<bool> access;
  late Future<AdminAnalyticsReport> analyticsResult;
  Future<List<WebAdminRecord>>? searchResults;
  late Future<List<WebAdminRecord>> previewJobs;
  late Future<List<WebAdminRecord>> previewProfiles;
  late Future<List<WebAdminRecord>> previewApplications;
  Timer? searchDebounce;
  AdminWorkspace section = AdminWorkspace.overview;
  AdminRequestTab requestTab = AdminRequestTab.support;
  String searchText = '';
  String previewRole = 'worker';
  String previewSection = 'Home';
  String previewSearch = '';
  String analyticsTab = 'revenue';
  String analyticsPeriod = 'month';

  @override
  void initState() {
    super.initState();
    access = admin.isAuthorized(widget.user.uid);
    _refreshOverview();
    previewJobs = searchService.publicPreviewJobs(widget.user.uid);
    previewProfiles = searchService.previewProfiles(widget.user.uid, previewRole);
    previewApplications = searchService.previewApplications(widget.user.uid);
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    super.dispose();
  }

  void _refreshOverview() {
    analyticsResult = analytics.load(analyticsTab, analyticsPeriod);
  }

  void _search(String value) {
    searchDebounce?.cancel();
    setState(() {
      searchText = value;
      searchResults = null;
    });
    if (value.trim().length < 2) return;
    searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        setState(
            () => searchResults = searchService.search(widget.user.uid, value));
      }
    });
  }

  void _selectSection(AdminWorkspace value) {
    searchDebounce?.cancel();
    setState(() {
      section = value;
      searchText = '';
      searchResults = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: access,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
              body: Center(
                  child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not verify administrator access.'),
              TextButton(
                onPressed: () => setState(() {
                  access = admin.isAuthorized(widget.user.uid);
                }),
                child: const Text('Retry'),
              ),
            ],
          )));
        }
        if (snapshot.data != true) {
          return const Scaffold(
              body: Center(child: Text('Administrator access required.')));
        }
        return Scaffold(
          backgroundColor: WebTheme.page,
          body: LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 850;
            return narrow
                ? Column(children: [
                    _navigation(horizontal: true),
                    Expanded(child: _content()),
                  ])
                : Row(children: [
                    SizedBox(width: 220, child: _navigation(horizontal: false)),
                    Expanded(child: _content()),
                  ]);
          }),
        );
      },
    );
  }

  Widget _navigation({required bool horizontal}) {
    final destinations = <(AdminWorkspace, IconData, String)>[
      (AdminWorkspace.overview, Icons.dashboard_outlined, 'Overview'),
      (AdminWorkspace.requests, Icons.inbox_outlined, 'Requests'),
      (AdminWorkspace.search, Icons.search, 'Search'),
      (AdminWorkspace.view, Icons.visibility_outlined, 'View'),
    ];
    final items = [
      for (final (value, icon, label) in destinations)
        Padding(
          padding: const EdgeInsets.all(3),
          child: TextButton.icon(
            onPressed: () => _selectSection(value),
            icon: Icon(icon, size: 20),
            label: Text(label),
            style: TextButton.styleFrom(
              foregroundColor:
                  section == value ? WebTheme.accent : WebTheme.ink,
              backgroundColor: section == value ? WebTheme.accentSoft : null,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ),
    ];
    return Container(
      color: WebTheme.surface,
      child: horizontal
          ? SafeArea(
              bottom: false,
              child: Column(children: [
                _identity(compact: true),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: items),
                ),
              ]),
            )
          : SafeArea(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _identity(compact: false),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    ...items,
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out'),
                    ),
                    const SizedBox(height: 16),
                  ]),
            ),
    );
  }

  Widget _identity({required bool compact}) => Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          const Icon(Icons.admin_panel_settings_outlined,
              color: WebTheme.accent),
          const SizedBox(width: 10),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('STROYKA',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                Text('Admin console', style: WebTypography.metadata),
              ])),
          if (compact)
            IconButton(
              tooltip: 'Sign out',
              onPressed: () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout),
            ),
        ]),
      );

  Widget _content() {
    final heading = switch (section) {
      AdminWorkspace.overview => 'Overview',
      AdminWorkspace.requests => 'Requests',
      AdminWorkspace.search => 'Search',
      AdminWorkspace.view => 'View',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: WebTheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(children: [
          Expanded(child: Text(heading, style: WebTypography.sectionTitle)),
          Text(widget.user.email ?? 'Admin', style: WebTypography.metadata),
        ]),
      ),
      if (section == AdminWorkspace.view)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          color: WebTheme.accentSoft,
          child: Row(children: [
            const Expanded(
                child: Text('ADMIN PREVIEW — READ ONLY',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            TextButton.icon(
              onPressed: () => _selectSection(AdminWorkspace.overview),
              icon: const Icon(Icons.close),
              label: const Text('Exit Preview'),
            ),
          ]),
        ),
      Expanded(
          child: switch (section) {
        AdminWorkspace.overview => _overview(),
        AdminWorkspace.requests => _requests(),
        AdminWorkspace.search => _searchPage(),
        AdminWorkspace.view => _viewPage(),
      }),
    ]);
  }

  Widget _overview() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Analytics', style: WebTypography.panelTitle)),
            IconButton(tooltip: 'Refresh', onPressed: () => setState(_refreshOverview),
                icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'revenue', label: Text('Revenue')),
                ButtonSegment(value: 'vacancies', label: Text('Vacancies')),
                ButtonSegment(value: 'hires', label: Text('Hires')),
                ButtonSegment(value: 'users', label: Text('Users')),
              ],
              selected: {analyticsTab},
              onSelectionChanged: (value) => setState(() {
                analyticsTab = value.first;
                _refreshOverview();
              }),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'month', label: Text('MONTH')),
              ButtonSegment(value: 'year', label: Text('YEAR')),
            ],
            selected: {analyticsPeriod},
            onSelectionChanged: (value) => setState(() {
              analyticsPeriod = value.first;
              _refreshOverview();
            }),
          ),
          const SizedBox(height: 20),
          FutureBuilder<AdminAnalyticsReport>(
            future: analyticsResult,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _error('Analytics are unavailable: ${snapshot.error}',
                    () => setState(_refreshOverview));
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final report = snapshot.data!;
              final currency = analyticsTab == 'revenue';
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final entry in report.kpis.entries)
                    _MetricTile(label: entry.key, value: entry.value,
                        currency: currency && (entry.key.contains('revenue') ||
                            entry.key.contains('Direct Debit')),
                        percent: entry.key.contains('percent')),
                ]),
                const SizedBox(height: 22),
                if (report.series.isNotEmpty)
                  _AnalyticsChart(report: report, currency: currency),
                for (final note in report.notes)
                  Padding(padding: const EdgeInsets.only(top: 12),
                    child: Text(note, style: WebTypography.metadata)),
              ]);
            },
          ),
        ]),
      );

  Widget _requests() {
    final mode = switch (requestTab) {
      AdminRequestTab.support => WebAdminSection.requests,
      AdminRequestTab.approvals => WebAdminSection.jobs,
      AdminRequestTab.billing => WebAdminSection.requests,
      AdminRequestTab.inbox => WebAdminSection.inbox,
    };
    final collections = switch (requestTab) {
      AdminRequestTab.support => ['support_requests', 'reports'],
      AdminRequestTab.billing => ['payment_requests'],
      _ => null,
    };
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(16),
        child: SegmentedButton<AdminRequestTab>(
          segments: const [
            ButtonSegment(
                value: AdminRequestTab.support,
                label: Text('Support Requests')),
            ButtonSegment(
                value: AdminRequestTab.approvals,
                label: Text('Approval Requests')),
            ButtonSegment(
                value: AdminRequestTab.billing,
                label: Text('Billing Requests')),
            ButtonSegment(value: AdminRequestTab.inbox, label: Text('Inbox')),
          ],
          selected: {requestTab},
          onSelectionChanged: (value) =>
              setState(() => requestTab = value.first),
        ),
      ),
      Expanded(
          child: WebAdminProfilePage(
        key: ValueKey('admin-requests:${requestTab.name}'),
        uid: widget.user.uid,
        profile: widget.profile,
        onClose: () {},
        onOpenProfile: (id, role) async {
          try {
            final record = await searchService.user(widget.user.uid, id);
            if (mounted && record != null) _showRecord(record);
          } catch (error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not open profile: $error')),
              );
            }
          }
        },
        initialSection: mode,
        embedded: true,
        requestCollections: collections,
      )),
    ]);
  }

  Widget _searchPage() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('People, companies and vacancies',
              style: WebTypography.panelTitle),
          const SizedBox(height: 12),
          TextField(
            onChanged: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Name, email, phone, company, vacancy or ID',
            ),
          ),
          const SizedBox(height: 16),
          _searchResults(onSelect: _showRecord),
        ]),
      );

  Widget _searchResults(
      {required ValueChanged<WebAdminRecord> onSelect, String? role}) {
    if (searchText.trim().length < 2) {
      return const Text('Enter at least two characters.');
    }
    if (searchResults == null) return const LinearProgressIndicator();
    return FutureBuilder<List<WebAdminRecord>>(
      future: searchResults,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _error('Search failed.', () => _search(searchText));
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final items = role == null
            ? snapshot.data!
            : snapshot.data!
                .where((record) =>
                    record.collection == 'users' && record.data['role'] == role)
                .toList();
        if (items.isEmpty) return const Text('No matching records.');
        return Column(children: [
          for (final item in items)
            ListTile(
              title: Text(item.title.isEmpty ? item.id : item.title),
              subtitle: Text('${item.collection == 'jobs' ? 'Vacancy' :
                  item.data['role'] == 'employer' ? 'Employer / Company' :
                  item.data['role'] == 'worker' ? 'Worker' : 'Account'}  ${item.text}',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onSelect(item),
            ),
        ]);
      },
    );
  }

  void _showRecord(WebAdminRecord record) {
    if (record.collection == 'users') {
      _showUserProfile(record);
      return;
    }
    const fields = [
      'role',
      'email',
      'phone',
      'companyName',
      'status',
      'moderationStatus',
      'trade',
      'site',
      'postcode',
      'ownerId',
      'workerId',
      'employerId',
    ];
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(record.title.isEmpty ? record.id : record.title),
              content: SizedBox(
                  width: 500,
                  child: SingleChildScrollView(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (section == AdminWorkspace.view)
                        Container(
                          width: double.infinity,
                          color: WebTheme.accentSoft,
                          padding: const EdgeInsets.all(8),
                          child: const Text('ADMIN PREVIEW — READ ONLY',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      SelectableText('${record.collection}/${record.id}'),
                      const SizedBox(height: 12),
                      for (final field in fields)
                        if (record.data[field]?.toString().isNotEmpty == true)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text('$field: ${record.data[field]}')),
                    ],
                  ))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ],
            ));
  }

  Future<void> _showUserProfile(WebAdminRecord initial,
      {bool readOnly = false}) async {
    var current = initial;
    var saving = false;
    final portfolio = initial.data['role'] == 'worker'
        ? WebProfileDataService().loadWorkerPortfolio(initial.id)
        : null;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) {
          final profile = WebProfileData(id: current.id, data: current.data);
          final held = ModerationHoldService.isProfileHeld(current.data);
          return AlertDialog(
            title: Text(profile.displayName),
            content: SizedBox(
              width: 620,
              height: 540,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (readOnly)
                      Container(
                        width: double.infinity,
                        color: WebTheme.accentSoft,
                        padding: const EdgeInsets.all(8),
                        child: const Text('ADMIN PREVIEW — READ ONLY',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    SizedBox(
                      height: 180,
                      child: Stack(children: [
                        Positioned.fill(child: profile.headerUrl.isEmpty
                            ? const ColoredBox(color: WebTheme.deep)
                            : WebRemoteImage(url: profile.headerUrl, fit: BoxFit.cover)),
                        Positioned(left: 16, bottom: 12,
                            child: WebCircleImage(url: profile.avatarUrl, size: 80,
                                fallbackIcon: profile.role == 'worker'
                                    ? Icons.person_outline : Icons.business_outlined)),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Text(profile.displayName, style: WebTypography.sectionTitle),
                    Text(profile.role == 'worker' ? 'Worker profile' : 'Company profile',
                        style: WebTypography.metadata),
                    if (profile.trade.isNotEmpty) Text(profile.trade),
                    if (profile.bio.isNotEmpty) Padding(
                      padding: const EdgeInsets.only(top: 12), child: Text(profile.bio)),
                    if (profile.location.isNotEmpty) Text(profile.location),
                    if (profile.city.isNotEmpty) Text(profile.city),
                    if (profile.website.isNotEmpty) Text(profile.website),
                    if (profile.role == 'worker') ...[
                      const SizedBox(height: 18),
                      WebWorkerReviews(workerId: current.id, ownProfile: false),
                      const SizedBox(height: 18),
                      const Text('Portfolio', style: WebTypography.cardTitle),
                      FutureBuilder(
                        future: portfolio,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Text('Portfolio unavailable.');
                          }
                          final items = snapshot.data!;
                          if (items.isEmpty) return const Text('No portfolio photos.');
                          return Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final item in items)
                              SizedBox(width: 110, height: 90,
                                child: WebRemoteImage(url: item.url, fit: BoxFit.cover)),
                          ]);
                        },
                      ),
                    ],
                    if (profile.role == 'employer' && profile.companyPhotos.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text('Company photos', style: WebTypography.cardTitle),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final url in profile.companyPhotos.take(12))
                          SizedBox(width: 110, height: 90,
                            child: WebRemoteImage(url: url, fit: BoxFit.cover)),
                      ]),
                    ],
                    const Divider(height: 30),
                    const Text('Admin metadata', style: WebTypography.cardTitle),
                    SelectableText('UID: ${current.id}'),
                    if (profile.email.isNotEmpty) SelectableText('Email: ${profile.email}'),
                    if (profile.phone.isNotEmpty) SelectableText('Phone: ${profile.phone}'),
                    Text('Status: ${held ? 'Blocked' : 'Active'}'),
                  ],
                ),
              ),
            ),
            actions: [
              if (!readOnly && current.id != widget.user.uid)
                TextButton(
                  onPressed: saving ? null : () async {
                    final reason = TextEditingController();
                    try {
                      final confirmed = await showDialog<bool>(
                        context: dialogContext,
                        builder: (confirmContext) => AlertDialog(
                          title: Text(held ? 'Unblock profile?' : 'Block profile?'),
                          content: held
                              ? Text('Restore ${profile.displayName} to active status?')
                              : TextField(controller: reason,
                                  decoration: const InputDecoration(labelText: 'Reason'),
                                  maxLines: 2),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(confirmContext, false),
                                child: const Text('Cancel')),
                            FilledButton(onPressed: () {
                              if (!held && reason.text.trim().isEmpty) return;
                              Navigator.pop(confirmContext, true);
                            }, child: Text(held ? 'Unblock' : 'Block')),
                          ],
                        ),
                      );
                      if (confirmed != true || !dialogContext.mounted) return;
                      update(() => saving = true);
                      if (held) {
                        await admin.restoreUser(current.id);
                      } else {
                        await admin.holdUser(current, reason.text.trim());
                      }
                      final refreshed = await searchService.user(widget.user.uid, current.id);
                      if (dialogContext.mounted && refreshed != null) {
                        update(() { current = refreshed; saving = false; });
                        if (mounted && searchText.trim().length >= 2) {
                          setState(() => searchResults =
                              searchService.search(widget.user.uid, searchText));
                        }
                      }
                    } catch (error) {
                      if (dialogContext.mounted) {
                        update(() => saving = false);
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text('Could not update profile: $error')));
                      }
                    } finally {
                      reason.dispose();
                    }
                  },
                  child: Text(held ? 'Unblock' : 'Block'),
                ),
              TextButton(onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  void _showJobPreview(WebAdminRecord record) {
    final job = Job.fromFirestore(record.id, record.data);
    showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
              child: SizedBox(
                width: 900,
                height: 700,
                child: Column(children: [
                  Row(children: [
                    const SizedBox(width: 16),
                    const Expanded(
                        child: Text('Vacancy preview',
                            style: WebTypography.panelTitle)),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                  Container(
                    width: double.infinity,
                    color: WebTheme.accentSoft,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: const Text('ADMIN PREVIEW — READ ONLY',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: WebJobDetailsPanel(
                    job: job,
                    isWorker: previewRole == 'worker',
                    isEmployerOwner: previewRole == 'employer',
                  )),
                ]),
              ),
            ));
  }

  Widget _viewPage() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Product preview', style: WebTypography.panelTitle),
          const SizedBox(height: 8),
          const Text('Inspect live product content without changing your Admin identity.'),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'worker', label: Text('View as Worker')),
              ButtonSegment(value: 'employer', label: Text('View as Employer')),
            ],
            selected: {previewRole},
            onSelectionChanged: (value) => setState(() {
              previewRole = value.first;
              previewSection = 'Home';
              previewProfiles = searchService.previewProfiles(
                  widget.user.uid, previewRole);
            }),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Home', label: Text('Home')),
                ButtonSegment(value: 'Jobs', label: Text('Jobs')),
                ButtonSegment(value: 'Map', label: Text('Map')),
                ButtonSegment(value: 'Applications', label: Text('Applications')),
                ButtonSegment(value: 'Profiles', label: Text('Profiles')),
              ],
              selected: {previewSection},
              onSelectionChanged: (value) => setState(() => previewSection = value.first),
            ),
          ),
          const SizedBox(height: 16),
          if (previewSection == 'Profiles')
            FutureBuilder<List<WebAdminRecord>>(
              future: previewProfiles,
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text('Could not load profiles.');
                if (!snapshot.hasData) return const LinearProgressIndicator();
                if (snapshot.data!.isEmpty) return const Text('No active profiles.');
                return Column(children: [
                  for (final record in snapshot.data!)
                    ListTile(
                      leading: WebCircleImage(
                        url: WebProfileData(id: record.id, data: record.data).avatarUrl,
                        size: 40,
                        fallbackIcon: previewRole == 'worker'
                            ? Icons.person_outline : Icons.business_outlined),
                      title: Text(WebProfileData(id: record.id, data: record.data).displayName),
                      subtitle: Text(record.data['trade']?.toString() ??
                          record.data['companyName']?.toString() ?? ''),
                      onTap: () => _showUserProfile(record, readOnly: true),
                    ),
                ]);
              },
            )
          else if (previewSection == 'Applications')
            FutureBuilder<List<WebAdminRecord>>(
              future: previewApplications,
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text('Could not load applications.');
                if (!snapshot.hasData) return const LinearProgressIndicator();
                if (snapshot.data!.isEmpty) return const Text('No applications.');
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Platform activity preview; no account is impersonated.',
                      style: WebTypography.metadata),
                  for (final record in snapshot.data!)
                    ListTile(
                      title: Text(record.data['jobTitle']?.toString() ?? record.id),
                      subtitle: Text(record.status),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showRecord(record),
                    ),
                ]);
              },
            )
          else ...[
          Row(children: [
            const Expanded(child: Text('Live public vacancies', style: WebTypography.sectionTitle)),
            IconButton(
              tooltip: 'Refresh preview',
              onPressed: () => setState(() {
                previewJobs = searchService.publicPreviewJobs(widget.user.uid);
              }),
              icon: const Icon(Icons.refresh),
            ),
          ]),
          FutureBuilder<List<WebAdminRecord>>(
            future: previewJobs,
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Text('Could not load public vacancies.');
              if (!snapshot.hasData) return const LinearProgressIndicator();
              if (snapshot.data!.isEmpty) return const Text('No live vacancies.');
              final jobs = snapshot.data!.where((job) {
                final text = previewSearch.trim().toLowerCase();
                return text.isEmpty || [job.title, job.text, job.id]
                    .join(' ').toLowerCase().contains(text);
              }).toList();
              if (previewSection == 'Map') {
                return _AdminPreviewMap(jobs: jobs,
                    onOpenJob: _showJobPreview);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (previewSection == 'Home')
                  Padding(padding: const EdgeInsets.only(bottom: 16),
                    child: Text(previewRole == 'worker'
                      ? 'Worker home · ${snapshot.data!.length} live vacancies'
                      : 'Employer home · public vacancy activity',
                      style: WebTypography.cardTitle)),
                TextField(
                  onChanged: (value) => setState(() => previewSearch = value),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
                    hintText: 'Search visible vacancies'),
                ),
                const SizedBox(height: 16),
                if (jobs.isEmpty) const Text('No matching vacancies.'),
                for (final record in jobs)
                  Padding(padding: const EdgeInsets.only(bottom: 10),
                    child: WebWorkerVacancyCard(
                      job: Job.fromFirestore(record.id, record.data),
                      selected: false,
                      saved: false,
                      showApplicationStatus: false,
                      showVacancyLifecycleStatus: previewRole == 'employer',
                      onTap: () => _showJobPreview(record),
                    )),
              ]);
            },
          ),
          ],
        ]),
      );

  Widget _error(String message, VoidCallback retry) => Row(children: [
        Expanded(child: Text(message)),
        TextButton(onPressed: retry, child: const Text('Retry')),
      ]);
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value,
    required this.currency, required this.percent});

  final String label;
  final num? value;
  final bool currency;
  final bool percent;

  @override
  Widget build(BuildContext context) => Container(
    width: 190,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: WebTheme.surface,
      border: Border.all(color: WebTheme.border), borderRadius: BorderRadius.circular(6)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value == null ? 'Unavailable' : currency
          ? '£${(value! / 100).toStringAsFixed(2)}'
          : percent ? '$value%' : '$value',
        style: WebTypography.sectionTitle),
      const SizedBox(height: 4),
      Text(label, style: WebTypography.metadata),
    ]),
  );
}

class _AnalyticsChart extends StatelessWidget {
  const _AnalyticsChart({required this.report, required this.currency});

  final AdminAnalyticsReport report;
  final bool currency;

  @override
  Widget build(BuildContext context) {
    final maxValue = report.series.values.expand((values) => values)
        .fold<num>(0, (current, value) => value > current ? value : current);
    final entries = report.series.entries.toList();
    const colors = [WebTheme.accent, Color(0xFFB46B2B), Color(0xFF7A6BAA)];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: WebTheme.surface,
        border: Border.all(color: WebTheme.border), borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 18, runSpacing: 8, children: [
          for (var seriesIndex = 0; seriesIndex < entries.length; seriesIndex++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10,
                color: colors[seriesIndex % colors.length]),
              const SizedBox(width: 6),
              Text(entries[seriesIndex].key),
            ]),
        ]),
        const SizedBox(height: 16),
        SizedBox(height: 188,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var index = 0; index < report.keys.length; index++)
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                SizedBox(height: 158, child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var seriesIndex = 0; seriesIndex < entries.length; seriesIndex++)
                      Expanded(child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Tooltip(
                          message: '${report.keys[index]}  ${entries[seriesIndex].key}: '
                              '${currency ? '£${(entries[seriesIndex].value[index] / 100).toStringAsFixed(2)}' : entries[seriesIndex].value[index]}',
                          child: InkWell(
                            onTap: () => showDialog<void>(context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: Text(report.keys[index]),
                                content: Text('${entries[seriesIndex].key}: '
                                    '${currency ? '£${(entries[seriesIndex].value[index] / 100).toStringAsFixed(2)}' : entries[seriesIndex].value[index]}'),
                                actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('Close'))],
                              )),
                            child: Container(
                              height: maxValue == 0 ? 4 :
                                4 + 150 * entries[seriesIndex].value[index] / maxValue,
                              color: colors[seriesIndex % colors.length],
                            ),
                          ),
                        ),
                      )),
                  ],
                )),
                const SizedBox(height: 7),
                SizedBox(height: 20, child: Text(
                  index % (report.keys.length > 12 ? 5 : 1) == 0
                    ? report.keys[index].substring(report.keys[index].length - 2) : '',
                  style: WebTypography.metadata)),
              ])),
          ]),
        ),
      ]),
    );
  }
}

class _AdminPreviewMap extends StatelessWidget {
  const _AdminPreviewMap({required this.jobs, required this.onOpenJob});

  final List<WebAdminRecord> jobs;
  final ValueChanged<WebAdminRecord> onOpenJob;

  @override
  Widget build(BuildContext context) {
    final located = jobs.map((record) => (
      record, Job.fromFirestore(record.id, record.data)))
      .where((entry) => entry.$2.lat != 0 && entry.$2.lng != 0).toList();
    final center = located.isEmpty ? const LatLng(53.4808, -2.2426)
        : LatLng(located.first.$2.lat, located.first.$2.lng);
    return SizedBox(height: 520, child: FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: located.isEmpty ? 6 : 9,
        minZoom: 3, maxZoom: 18,
        interactionOptions: const InteractionOptions(flags:
          InteractiveFlag.drag | InteractiveFlag.pinchMove |
          InteractiveFlag.pinchZoom | InteractiveFlag.scrollWheelZoom |
          InteractiveFlag.doubleTapZoom)),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.makaiov.builderjob'),
        MarkerLayer(markers: [
          for (final entry in located)
            Marker(point: LatLng(entry.$2.lat, entry.$2.lng),
              width: 42, height: 42,
              child: IconButton(
                tooltip: entry.$2.displayTitle,
                onPressed: () => onOpenJob(entry.$1),
                icon: const Icon(Icons.location_on, color: WebTheme.accent),
              )),
        ]),
      ],
    ));
  }
}

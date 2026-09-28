import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/job.dart';
import '../pages/jobs/web_job_details_panel.dart';
import '../pages/profile/web_admin_profile_page.dart';
import '../services/web_admin_profile_service.dart';
import '../services/web_profile_data_service.dart';
import '../theme/web_theme.dart';
import '../widgets/web_remote_image.dart';
import 'admin_overview_service.dart';
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
  final overview = AdminOverviewService();
  final searchService = AdminSearchService();
  late Future<bool> access;
  late Future<Map<String, int?>> counts;
  late Future<Map<String, List<int>>> trends;
  Future<List<WebAdminRecord>>? searchResults;
  Future<List<WebAdminRecord>>? previewRecords;
  Timer? searchDebounce;
  AdminWorkspace section = AdminWorkspace.overview;
  AdminRequestTab requestTab = AdminRequestTab.support;
  String searchText = '';
  String previewRole = 'worker';
  String previewTab = 'Profile';
  WebAdminRecord? previewTarget;
  int days = 30;

  @override
  void initState() {
    super.initState();
    access = admin.isAuthorized(widget.user.uid);
    _refreshOverview();
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    super.dispose();
  }

  void _refreshOverview() {
    counts = overview.loadCounts(widget.user.uid);
    trends = overview.loadTrends(widget.user.uid, days: days);
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

  void _openPreview(WebAdminRecord record) {
    final role = record.data['role']?.toString();
    if (role != previewRole) return;
    setState(() {
      previewTarget = record;
      previewTab = 'Profile';
      previewRecords =
          searchService.previewRecords(widget.user.uid, record.id, role!);
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
      if (section == AdminWorkspace.view && previewTarget != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          color: WebTheme.accentSoft,
          child: Row(children: [
            const Expanded(
                child: Text('ADMIN PREVIEW — READ ONLY',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            TextButton.icon(
              onPressed: () => setState(() {
                previewTarget = null;
                previewRecords = null;
              }),
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
            const Expanded(
                child:
                    Text('Platform activity', style: WebTypography.panelTitle)),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => setState(_refreshOverview),
              icon: const Icon(Icons.refresh),
            ),
          ]),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, int?>>(
            future: counts,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _error('Could not load metrics.',
                    () => setState(_refreshOverview));
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return LayoutBuilder(builder: (context, constraints) {
                final width =
                    constraints.maxWidth < 560 ? constraints.maxWidth : 190.0;
                return Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final entry in snapshot.data!.entries)
                    SizedBox(
                        width: width,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: WebTheme.surface,
                            border: Border.all(color: WebTheme.border),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.value?.toString() ?? 'Unavailable',
                                    style: WebTypography.sectionTitle),
                                const SizedBox(height: 4),
                                Text(entry.key, style: WebTypography.metadata),
                              ]),
                        )),
                ]);
              });
            },
          ),
          const SizedBox(height: 28),
          Row(children: [
            const Expanded(
                child: Text('Recent trends', style: WebTypography.panelTitle)),
            DropdownButton<int>(
              value: days,
              items: const [
                DropdownMenuItem(value: 7, child: Text('7 days')),
                DropdownMenuItem(value: 30, child: Text('30 days')),
                DropdownMenuItem(value: 90, child: Text('90 days')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  days = value;
                  trends = overview.loadTrends(widget.user.uid, days: days);
                });
              },
            ),
          ]),
          const Text('Recent records only (up to 250 per series).',
              style: WebTypography.metadata),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, List<int>>>(
            future: trends,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _error(
                    'Could not load trends.', () => setState(_refreshOverview));
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              if (snapshot.data!.isEmpty) {
                return const Text('Trend data is unavailable.');
              }
              return Column(children: [
                for (final entry in snapshot.data!.entries)
                  _TrendPanel(title: entry.key, values: entry.value),
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
        onOpenProfile: (id, role) {},
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
              subtitle: Text('${item.collection}  ${item.text}',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onSelect(item),
            ),
        ]);
      },
    );
  }

  void _showRecord(WebAdminRecord record) {
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
                  Expanded(child: WebJobDetailsPanel(job: job)),
                ]),
              ),
            ));
  }

  Widget _viewPage() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Admin preview', style: WebTypography.panelTitle),
          const SizedBox(height: 8),
          const Text('Inspect account data without signing in as the user.'),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'worker', label: Text('View as Worker')),
              ButtonSegment(value: 'employer', label: Text('View as Employer')),
            ],
            selected: {previewRole},
            onSelectionChanged: (value) => setState(() {
              previewRole = value.first;
              previewTarget = null;
              previewRecords = null;
            }),
          ),
          const SizedBox(height: 16),
          if (previewTarget == null) ...[
            TextField(
              onChanged: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Find a Worker or Employer',
              ),
            ),
            const SizedBox(height: 12),
            _searchResults(role: previewRole, onSelect: _openPreview),
          ] else ...[
            _previewIdentity(),
            const SizedBox(height: 12),
            Text(
                previewTarget!.title.isEmpty
                    ? previewTarget!.id
                    : previewTarget!.title,
                style: WebTypography.sectionTitle),
            Text('$previewRole  •  ${previewTarget!.id}',
                style: WebTypography.metadata),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Profile', label: Text('Profile')),
                  ButtonSegment(value: 'Jobs', label: Text('Jobs')),
                  ButtonSegment(
                      value: 'Applications', label: Text('Applications')),
                  ButtonSegment(value: 'Chats', label: Text('Chats')),
                ],
                selected: {previewTab},
                onSelectionChanged: (value) =>
                    setState(() => previewTab = value.first),
              ),
            ),
            const SizedBox(height: 18),
            if (previewTab == 'Profile')
              for (final field in const [
                'email',
                'phone',
                'trade',
                'companyName',
                'status',
                'addressLine1',
                'townCity',
                'postcode'
              ])
                if (previewTarget!.data[field]?.toString().isNotEmpty == true)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('$field: ${previewTarget!.data[field]}')),
            if (previewTab != 'Profile')
              FutureBuilder<List<WebAdminRecord>>(
                future: previewRecords,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('Could not load preview records.');
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final collection = previewTab.toLowerCase();
                  final items = snapshot.data!
                      .where((item) => item.collection == collection)
                      .toList();
                  if (items.isEmpty) {
                    return const Text('No recent records.');
                  }
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final item in items)
                          ListTile(
                            title:
                                Text(item.title.isEmpty ? item.id : item.title),
                            subtitle: Text(item.status.isNotEmpty
                                ? item.status
                                : (item.data['lastMessage'] ?? item.text)
                                    .toString()),
                            onTap: () => item.collection == 'jobs'
                                ? _showJobPreview(item)
                                : _showRecord(item),
                          ),
                      ]);
                },
              ),
          ],
        ]),
      );

  Widget _previewIdentity() {
    final profile = WebProfileData(
      id: previewTarget!.id,
      data: previewTarget!.data,
    );
    return SizedBox(
        height: 135,
        child: Stack(children: [
          Positioned.fill(
              child: profile.headerUrl.isEmpty
                  ? const ColoredBox(color: WebTheme.deep)
                  : WebRemoteImage(url: profile.headerUrl, fit: BoxFit.cover)),
          Positioned(
              left: 16,
              bottom: 12,
              child: WebCircleImage(
                url: profile.avatarUrl,
                size: 70,
                fallbackIcon: previewRole == 'worker'
                    ? Icons.person_outline
                    : Icons.business_outlined,
              )),
        ]));
  }

  Widget _error(String message, VoidCallback retry) => Row(children: [
        Expanded(child: Text(message)),
        TextButton(onPressed: retry, child: const Text('Retry')),
      ]);
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.title, required this.values});

  final String title;
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(
        0, (current, value) => value > current ? value : current);
    final total = values.fold<int>(0, (current, value) => current + value);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: WebTheme.surface,
          border: Border.all(color: WebTheme.border),
          borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title  •  $total recent', style: WebTypography.cardTitle),
        const SizedBox(height: 12),
        SizedBox(
            height: 94,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final value in values)
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    height: maxValue == 0 ? 2 : 2 + 90 * value / maxValue,
                    color: WebTheme.accent,
                  ),
                )),
            ])),
      ]),
    );
  }
}

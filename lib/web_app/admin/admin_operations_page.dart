import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/web_admin_profile_service.dart';
import '../theme/web_theme.dart';
import 'admin_command_service.dart';

class AdminOperationsPage extends StatefulWidget {
  const AdminOperationsPage({
    super.key,
    required this.adminUid,
    required this.onOpenRecord,
    required this.onOpenUser,
    required this.onOpenSite,
    this.initialView = AdminOperationalView.jobs,
    this.service,
  });

  final String adminUid;
  final AdminOperationalView initialView;
  final AdminCommandService? service;
  final ValueChanged<WebAdminRecord> onOpenRecord;
  final ValueChanged<String> onOpenUser;
  final ValueChanged<String> onOpenSite;

  @override
  State<AdminOperationsPage> createState() => _AdminOperationsPageState();
}

class _AdminOperationsPageState extends State<AdminOperationsPage> {
  late final AdminCommandService service =
      widget.service ?? AdminCommandService();
  late AdminOperationalView view = widget.initialView;
  final rows = <WebAdminRecord>[];
  String? cursor;
  Object? error;
  bool loading = false;
  bool loaded = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (loading) return;
    final request = ++generation;
    final next = more ? cursor : null;
    setState(() {
      loading = true;
      error = null;
      if (!more) {
        rows.clear();
        cursor = null;
        loaded = false;
      }
    });
    try {
      final page = await service.load(widget.adminUid, view, cursor: next);
      if (!mounted || request != generation) return;
      setState(() {
        rows.addAll(page.records);
        cursor = page.nextCursor;
        loaded = true;
      });
    } catch (failure) {
      if (mounted && request == generation) setState(() => error = failure);
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  void _select(AdminOperationalView next) {
    if (view == next) return;
    generation++;
    setState(() {
      view = next;
      rows.clear();
      cursor = null;
      loaded = false;
      loading = false;
      error = null;
    });
    _load();
  }

  String _text(WebAdminRecord row, String key) =>
      row.data[key]?.toString().trim() ?? '';

  String _date(Object? value) {
    final date = value is Timestamp
        ? value.toDate()
        : value is DateTime
            ? value
            : value is String
                ? DateTime.tryParse(value)
                : null;
    if (date == null) return 'Not set';
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _relation(String label, String? id, ValueChanged<String> open) {
    if (id == null || id.isEmpty) return const SizedBox.shrink();
    return TextButton(
      onPressed: () => open(id),
      child: Text(label),
    );
  }

  Widget _row(WebAdminRecord row) {
    final data = row.data;
    final employerId =
        (data['ownerId'] ?? data['employerContextId'])?.toString();
    final siteId = data['siteId']?.toString();
    final workerId = data['workerId']?.toString();
    final title = switch (view) {
      AdminOperationalView.jobs => _text(row, 'title').isNotEmpty
          ? _text(row, 'title')
          : _text(row, 'trade'),
      AdminOperationalView.sites => _text(row, 'name'),
      AdminOperationalView.assignments =>
        _text(row, 'workerDisplayName').isNotEmpty
            ? _text(row, 'workerDisplayName')
            : 'Assignment',
      AdminOperationalView.subscriptions => _text(row, 'companyName').isNotEmpty
          ? _text(row, 'companyName')
          : 'Company',
    };
    final detail = switch (view) {
      AdminOperationalView.jobs => [
          _text(row, 'adminEmployerName'),
          _text(row, 'trade'),
          _text(row, 'site'),
          '${data['filledPositions'] ?? 0}/${data['positions'] ?? 1} filled',
          _text(row, 'status'),
          'Start ${_date(data['startDate'])}',
        ],
      AdminOperationalView.sites => [
          _text(row, 'adminEmployerName'),
          _text(row, 'city'),
          _text(row, 'status'),
          '${data['adminVacancyCount'] ?? 0} open vacancies',
          '${data['adminWorkforceCount'] ?? 0} assigned',
        ],
      AdminOperationalView.assignments => [
          _text(row, 'tradeName'),
          _text(row, 'siteName'),
          _text(row, 'status'),
          'Starts ${_date(data['startDate'])}',
          'Finishes ${_date(data['actualEndDate'] ?? data['expectedEndDate'])}',
        ],
      AdminOperationalView.subscriptions => [
          (data['planName'] ?? 'No plan').toString(),
          (data['subscriptionStatus'] ?? 'inactive').toString(),
          'Period ends ${_date(data['subscriptionEndsAt'] ?? data['trialEndsAt'])}',
          '${data['usedJobPosts'] ?? 0}/${data['vacancySlotLimit'] ?? 0} vacancy slots',
          '${data['invitationUsed'] ?? 0}/${data['invitationLimit'] ?? 0} invitations',
          if (data['addonStatus'] != null) 'Outreach: ${data['addonStatus']}',
        ],
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: WebTheme.surface,
        border: Border.all(color: WebTheme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListTile(
        title: Text(title.isEmpty ? 'Untitled' : title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail.where((part) => part.isNotEmpty).join(' · '),
                maxLines: 3, overflow: TextOverflow.ellipsis),
            Wrap(spacing: 4, children: [
              if (view == AdminOperationalView.jobs ||
                  view == AdminOperationalView.assignments)
                _relation('Employer', employerId, widget.onOpenUser),
              if (view == AdminOperationalView.assignments)
                _relation('Worker', workerId, widget.onOpenUser),
              if (view == AdminOperationalView.sites)
                _relation('Employer', employerId, widget.onOpenUser),
              if (view == AdminOperationalView.jobs ||
                  view == AdminOperationalView.assignments)
                _relation('Site', siteId, widget.onOpenSite),
            ]),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: view == AdminOperationalView.subscriptions
            ? () => widget.onOpenUser(row.id)
            : view == AdminOperationalView.assignments && siteId != null
                ? () => widget.onOpenSite(siteId)
                : () => widget.onOpenRecord(row),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
            child: Row(children: [
              const Expanded(
                  child: Text('Platform operations',
                      style: WebTypography.panelTitle)),
              IconButton(
                  tooltip: 'Refresh',
                  onPressed: loading ? null : _load,
                  icon: const Icon(Icons.refresh)),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SegmentedButton<AdminOperationalView>(
              segments: const [
                ButtonSegment(
                    value: AdminOperationalView.jobs, label: Text('Jobs')),
                ButtonSegment(
                    value: AdminOperationalView.sites, label: Text('Sites')),
                ButtonSegment(
                    value: AdminOperationalView.assignments,
                    label: Text('Assignments')),
                ButtonSegment(
                    value: AdminOperationalView.subscriptions,
                    label: Text('Subscriptions')),
              ],
              selected: {view},
              onSelectionChanged: (choice) => _select(choice.first),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: [
                if (error != null)
                  ListTile(
                    title: const Text('Could not load this section.'),
                    trailing: TextButton(
                      onPressed: () => _load(more: rows.isNotEmpty),
                      child: const Text('Retry'),
                    ),
                  ),
                if (loaded && rows.isEmpty)
                  const ListTile(title: Text('No records in this section.')),
                for (final row in rows) _row(row),
                if (cursor != null)
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: loading ? null : () => _load(more: true),
                      icon: const Icon(Icons.expand_more),
                      label: const Text('Load more'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
}

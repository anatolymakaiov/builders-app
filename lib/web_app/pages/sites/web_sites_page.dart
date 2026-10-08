import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/job.dart';
import '../../../services/operational_calendar.dart';
import '../../services/web_sites_service.dart';
import '../../services/workforce_planning_service.dart';
import '../../widgets/web_page_container.dart';

class WebSitesPage extends StatefulWidget {
  const WebSitesPage(
      {super.key,
      required this.employerId,
      this.onOpenJob,
      this.initialSiteId,
      this.onOpenCalendar,
      this.onOpenWorkforce});

  final String employerId;
  final ValueChanged<String>? onOpenJob;
  final String? initialSiteId;
  final ValueChanged<String>? onOpenCalendar;
  final ValueChanged<String>? onOpenWorkforce;

  @override
  State<WebSitesPage> createState() => _WebSitesPageState();
}

class _WebSitesPageState extends State<WebSitesPage> {
  final service = WebSitesService();
  late Stream<List<WebSite>> sites;
  WebSite? selected;
  bool showInactive = false;
  String? requestedSiteId;
  final Map<String, Future<List<CalendarEvent>>> upcomingBySite = {};
  final Map<String, Future<WorkforcePlan>> workforceBySite = {};

  @override
  void initState() {
    super.initState();
    sites = service.watchEmployerSites(widget.employerId);
    requestedSiteId = widget.initialSiteId;
  }

  @override
  void didUpdateWidget(covariant WebSitesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employerId != widget.employerId) {
      selected = null;
      upcomingBySite.clear();
      workforceBySite.clear();
      sites = service.watchEmployerSites(widget.employerId);
      requestedSiteId = widget.initialSiteId;
    } else if (oldWidget.initialSiteId != widget.initialSiteId) {
      selected = null;
      requestedSiteId = widget.initialSiteId;
    }
  }

  @override
  Widget build(BuildContext context) => WebPageContainer(
        child: StreamBuilder<List<WebSite>>(
          stream: sites,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                  child: Text('Could not load sites. Try again.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snapshot.data!;
            final visible = all
                .where((site) => showInactive
                    ? site.status != 'active'
                    : site.status == 'active')
                .toList();
            final current = selected == null
                ? all.where((site) => site.id == requestedSiteId).firstOrNull
                : all.where((site) => site.id == selected!.id).firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(
                    child: Text('Sites',
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w700)),
                  ),
                  FilledButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add site'),
                  ),
                ]),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Active')),
                    ButtonSegment(
                        value: true, label: Text('Completed / Archived')),
                  ],
                  selected: {showInactive},
                  onSelectionChanged: (value) => setState(() {
                    showInactive = value.first;
                    selected = null;
                  }),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(builder: (context, constraints) {
                    final compact = constraints.maxWidth < 760;
                    final list = ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final site = visible[index];
                        return ListTile(
                          selected: current?.id == site.id,
                          title: Text(site.name),
                          subtitle: Text([
                            site.city,
                            site.postcode,
                            if (_date(site.data['expectedEndDate']) != null)
                              'Finish ${_date(site.data['expectedEndDate'])}'
                          ].where((s) => s.isNotEmpty).join(' ')),
                          trailing: Text(_statusLabel(site.status)),
                          onTap: () => setState(() {
                            requestedSiteId = null;
                            selected = site;
                            upcomingBySite.clear();
                            workforceBySite.clear();
                          }),
                        );
                      },
                    );
                    if (visible.isEmpty && current == null) {
                      return Center(
                          child: Text(showInactive
                              ? 'No completed or archived sites.'
                              : 'No active sites yet.'));
                    }
                    if (compact) {
                      return current == null
                          ? list
                          : _detail(current,
                              onBack: () => setState(() => selected = null));
                    }
                    return Row(children: [
                      SizedBox(width: 320, child: list),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: current == null
                            ? const Center(child: Text('Select a site'))
                            : _detail(current),
                      ),
                    ]);
                  }),
                ),
              ],
            );
          },
        ),
      );

  Widget _detail(WebSite site, {VoidCallback? onBack}) {
    final jobs = FirebaseFirestore.instance
        .collection('jobs')
        .where('ownerId', isEqualTo: widget.employerId)
        .where('siteId', isEqualTo: site.id)
        .snapshots();
    final assignments = FirebaseFirestore.instance
        .collection('assignments')
        .where('employerContextId', isEqualTo: widget.employerId)
        .where('siteId', isEqualTo: site.id)
        .snapshots();
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (onBack != null)
        Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
                onPressed: onBack, icon: const Icon(Icons.arrow_back))),
      Row(children: [
        Expanded(
            child: Text(site.name,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700))),
        IconButton(
            tooltip: 'Edit site',
            onPressed: () => _edit(site),
            icon: const Icon(Icons.edit_outlined)),
        PopupMenuButton<String>(
          tooltip: 'Site status',
          onSelected: (status) => _changeStatus(site, status),
          itemBuilder: (_) => [
            for (final status in const ['active', 'completed', 'archived'])
              PopupMenuItem(value: status, child: Text(_statusLabel(status))),
          ],
        ),
        if (widget.onOpenCalendar != null)
          IconButton(
              tooltip: 'View in Calendar',
              onPressed: () => widget.onOpenCalendar!(site.id),
              icon: const Icon(Icons.calendar_month_outlined)),
      ]),
      Text([
        site.data['addressLine1'],
        site.city,
        site.data['region'],
        site.postcode
      ].whereType<String>().where((s) => s.isNotEmpty).join(', ')),
      Text('Status: ${_statusLabel(site.status)}'),
      if (_date(site.data['startDate']) != null)
        Text('Start: ${_date(site.data['startDate'])}'),
      if (_date(site.data['expectedEndDate']) != null)
        Text('Expected finish: ${_date(site.data['expectedEndDate'])}'),
      if ((site.data['description'] ?? '').toString().isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(site.data['description'].toString())),
      const SizedBox(height: 16),
      const Text('Overview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 8, children: [
        _summaryItem('Start', _date(site.data['startDate']) ?? 'Not set'),
        _summaryItem('Expected finish',
            _date(site.data['expectedEndDate']) ?? 'Not set'),
        _summaryItem('Status', _statusLabel(site.status)),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        const Expanded(
            child: Text('Workforce',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        if (widget.onOpenWorkforce != null)
          TextButton.icon(
              onPressed: () => widget.onOpenWorkforce!(site.id),
              icon: const Icon(Icons.groups_2_outlined),
              label: const Text('Open Workforce Planning')),
        IconButton(
            tooltip: 'Refresh workforce summary',
            onPressed: () => setState(() => workforceBySite.remove(site.id)),
            icon: const Icon(Icons.refresh)),
      ]),
      FutureBuilder<WorkforcePlan>(
        future: workforceBySite.putIfAbsent(site.id, () {
          final now = DateTime.now();
          return WorkforcePlanningService().load(
              employerId: widget.employerId,
              window: PlanningWindow.nextDays(now, 14),
              now: now,
              siteId: site.id);
        }),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Could not load workforce summary.');
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final summary = snapshot.data!.siteSummaries
              .where((item) => item.siteId == site.id)
              .firstOrNull;
          if (summary == null) return const Text('No workforce activity.');
          return Text('${summary.currentWorkers} working  ·  '
              '${summary.starting} starting  ·  ${summary.finishing} finishing  ·  '
              '${summary.openPositions} open positions  ·  '
              '${snapshot.data!.gapCount} to fill');
        },
      ),
      const SizedBox(height: 16),
      Row(children: [
        const Expanded(
            child: Text('Upcoming events',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        if (widget.onOpenCalendar != null)
          TextButton.icon(
              onPressed: () => widget.onOpenCalendar!(site.id),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Open calendar')),
      ]),
      FutureBuilder<List<CalendarEvent>>(
        future: upcomingBySite.putIfAbsent(
            '${site.id}:${site.data['updatedAt']}',
            () => OperationalCalendarService().loadSiteUpcoming(
                employerId: widget.employerId,
                siteId: site.id,
                siteData: site.data)),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Could not load site events.');
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final upcoming = snapshot.data!;
          if (upcoming.isEmpty) return const Text('No upcoming site events.');
          return Column(children: [
            Text(
                'Upcoming events: ${upcoming.length}${upcoming.length == 8 ? '+' : ''} · next 90 days'),
            for (final event in upcoming.take(5))
              ListTile(
                  dense: true,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(event.title),
                  subtitle: Text(
                      '${event.typeLabel} · ${event.date.day}/${event.date.month}/${event.date.year}'),
                  onTap: widget.onOpenCalendar == null
                      ? null
                      : () => widget.onOpenCalendar!(site.id)),
          ]);
        },
      ),
      const SizedBox(height: 16),
      const Text('Vacancies',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: jobs,
        builder: (context, snapshot) => snapshot.hasError
            ? const Text('Could not load vacancies.')
            : snapshot.hasData
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(
                            'Total: ${snapshot.data!.docs.length} · Active: ${snapshot.data!.docs.where((doc) => Job.fromFirestore(doc.id, doc.data()).isPubliclyVisible).length}'),
                        for (final doc in snapshot.data!.docs)
                          ListTile(
                              title: Text((doc.data()['title'] ?? 'Vacancy')
                                  .toString()),
                              subtitle:
                                  Text((doc.data()['status'] ?? '').toString()),
                              onTap: widget.onOpenJob == null
                                  ? null
                                  : () => widget.onOpenJob!(doc.id))
                      ])
                : const LinearProgressIndicator(),
      ),
      const SizedBox(height: 16),
      const Text('Workers / Assignments',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: assignments,
        builder: (context, snapshot) => snapshot.hasError
            ? const Text('Could not load assignments.')
            : snapshot.hasData
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text('Assigned workers: ${snapshot.data!.docs.where((doc) => [
                              'active',
                              'scheduled'
                            ].contains(doc.data()['status'])).map((doc) => doc.data()['workerId']).where((id) => id != null).toSet().length}'),
                        for (final doc in snapshot.data!.docs)
                          ListTile(
                            title: Text(
                                (doc.data()['workerDisplayName'] ?? 'Worker')
                                    .toString()),
                            subtitle: Text((doc.data()['tradeName'] ??
                                    doc.data()['tradeId'] ??
                                    '')
                                .toString()),
                            trailing: Text((doc.data()['status'] ?? 'scheduled')
                                .toString()),
                          ),
                      ])
                : const LinearProgressIndicator(),
      ),
    ]);
  }

  Widget _summaryItem(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD8E0E5)),
            borderRadius: BorderRadius.circular(4)),
        child: Text('$label: $value'),
      );

  String? _date(dynamic value) {
    if (value is! Timestamp) return null;
    final date = value.toDate();
    return '${date.day}/${date.month}/${date.year}';
  }

  String _statusLabel(String status) => switch (status) {
        'active' => 'Active',
        'completed' => 'Completed',
        'archived' => 'Archived',
        _ => status,
      };

  Future<void> _changeStatus(WebSite site, String status) async {
    if (status == site.status) return;
    if (status != 'active') {
      final activeJobs = await FirebaseFirestore.instance
          .collection('jobs')
          .where('ownerId', isEqualTo: widget.employerId)
          .where('siteId', isEqualTo: site.id)
          .get();
      final count = activeJobs.docs
          .where((doc) =>
              ['active', 'published', 'open'].contains(doc.data()['status']))
          .length;
      if (!mounted) return;
      final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(
                      '${status[0].toUpperCase()}${status.substring(1)} site?'),
                  content: Text(count > 0
                      ? '$count active vacancies remain linked. They will not be closed.'
                      : 'Vacancies and assignments will be preserved.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Confirm'))
                  ]));
      if (confirm != true) return;
    }
    try {
      await service.setStatus(site, status);
      if (mounted) setState(() => selected = null);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update site status.')));
      }
    }
  }

  Future<void> _edit([WebSite? site]) async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => WebSiteFormDialog(initial: site?.data));
    if (result == null) return;
    try {
      if (site == null) {
        await service.create(widget.employerId, result);
      } else {
        await service.update(site, result);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save site.')));
      }
    }
  }
}

class WebSiteFormDialog extends StatefulWidget {
  const WebSiteFormDialog({super.key, this.initial});
  final Map<String, dynamic>? initial;

  @override
  State<WebSiteFormDialog> createState() => _SiteFormState();
}

class _SiteFormState extends State<WebSiteFormDialog> {
  final form = GlobalKey<FormState>();
  DateTime? startDate;
  DateTime? expectedEndDate;
  late final fields = <String, TextEditingController>{
    for (final key in const [
      'name',
      'addressLine1',
      'addressLine2',
      'city',
      'region',
      'postcode',
      'country',
      'description'
    ])
      key: TextEditingController(text: (widget.initial?[key] ?? '').toString()),
  };

  @override
  void initState() {
    super.initState();
    startDate = (widget.initial?['startDate'] as Timestamp?)?.toDate();
    expectedEndDate =
        (widget.initial?['expectedEndDate'] as Timestamp?)?.toDate();
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.initial == null ? 'Add site' : 'Edit site'),
        content: SizedBox(
            width: 520,
            child: Form(
                key: form,
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final entry in fields.entries)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextFormField(
                            controller: entry.value,
                            maxLength: entry.key == 'description' ? 1000 : 120,
                            decoration:
                                InputDecoration(labelText: _label(entry.key)),
                            validator: (value) => [
                                      'name',
                                      'addressLine1',
                                      'city',
                                      'region',
                                      'postcode'
                                    ].contains(entry.key) &&
                                    (value?.trim().isEmpty ?? true)
                                ? 'Required'
                                : null)),
                  ListTile(
                      title: Text(startDate == null
                          ? 'Start date'
                          : 'Start: ${_dateText(startDate!)}'),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () => _pickDate(true)),
                  ListTile(
                      title: Text(expectedEndDate == null
                          ? 'Expected end date'
                          : 'Expected end: ${_dateText(expectedEndDate!)}'),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () => _pickDate(false)),
                ])))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (form.currentState?.validate() != true) return;
                if (startDate != null &&
                    expectedEndDate != null &&
                    expectedEndDate!.isBefore(startDate!)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Expected end must be after start.')));
                  return;
                }
                Navigator.pop(context, {
                  for (final entry in fields.entries)
                    entry.key: entry.value.text.trim(),
                  if (startDate != null)
                    'startDate': Timestamp.fromDate(startDate!),
                  if (expectedEndDate != null)
                    'expectedEndDate': Timestamp.fromDate(expectedEndDate!),
                });
              },
              child: const Text('Save'))
        ],
      );

  String _label(String key) => switch (key) {
        'name' => 'Site / Project name',
        'addressLine1' => 'Address',
        'addressLine2' => 'Address line 2',
        'city' => 'City',
        'region' => 'Region',
        'postcode' => 'Postcode',
        'country' => 'Country',
        _ => 'Description',
      };

  String _dateText(DateTime date) => '${date.day}/${date.month}/${date.year}';

  Future<void> _pickDate(bool start) async {
    final current = start ? startDate : expectedEndDate;
    final selected = await showDatePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDate: current ?? DateTime.now());
    if (selected != null && mounted) {
      setState(() {
        if (start) {
          startDate = selected;
        } else {
          expectedEndDate = selected;
        }
      });
    }
  }
}

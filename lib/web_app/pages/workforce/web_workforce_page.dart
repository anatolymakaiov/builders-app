import 'package:flutter/material.dart';

import '../../../services/job_taxonomy_service.dart';
import '../../services/workforce_planning_service.dart';
import '../../services/workforce_talent_request.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';

typedef WorkforcePlanLoader = Future<WorkforcePlan> Function({
  required String employerId,
  required PlanningWindow window,
  required DateTime now,
  String? siteId,
  String? tradeId,
});

class WebWorkforcePage extends StatefulWidget {
  const WebWorkforcePage(
      {super.key,
      required this.employerId,
      this.initialSiteId,
      this.navigationRequestId = 0,
      this.onOpenSite,
      this.onOpenCalendar,
      this.onOpenJob,
      this.onFindWorkers,
      this.loadPlan});

  final String employerId;
  final String? initialSiteId;
  final int navigationRequestId;
  final ValueChanged<String>? onOpenSite;
  final ValueChanged<String?>? onOpenCalendar;
  final ValueChanged<String>? onOpenJob;
  final ValueChanged<WorkforceTalentRequest>? onFindWorkers;
  final WorkforcePlanLoader? loadPlan;

  @override
  State<WebWorkforcePage> createState() => _WebWorkforcePageState();
}

enum _Horizon { week, twoWeeks, fourWeeks, custom }

class _WebWorkforcePageState extends State<WebWorkforcePage> {
  WorkforcePlanningService? service;
  _Horizon horizon = _Horizon.twoWeeks;
  DateTimeRange? customRange;
  String? siteId;
  String? tradeId;
  WorkforcePlan? plan;
  bool loading = true;
  String? error;
  int requestId = 0;

  @override
  void initState() {
    super.initState();
    siteId = widget.initialSiteId;
    _load();
  }

  @override
  void didUpdateWidget(covariant WebWorkforcePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employerId != widget.employerId ||
        oldWidget.navigationRequestId != widget.navigationRequestId) {
      siteId = widget.initialSiteId;
      tradeId = null;
      plan = null;
      _load();
    }
  }

  @override
  void dispose() {
    requestId++;
    super.dispose();
  }

  PlanningWindow _window(DateTime now) => switch (horizon) {
        _Horizon.week => _thisWeek(now),
        _Horizon.twoWeeks => PlanningWindow.nextDays(now, 14),
        _Horizon.fourWeeks => PlanningWindow.nextDays(now, 28),
        _Horizon.custom when customRange != null => PlanningWindow(
            planningDay(customRange!.start),
            planningDayPlus(customRange!.end, 1)),
        _ => PlanningWindow.nextDays(now, 14),
      };

  PlanningWindow _thisWeek(DateTime now) {
    final monday = planningDayPlus(now, 1 - now.weekday);
    return PlanningWindow(monday, planningDayPlus(monday, 7));
  }

  Future<void> _load() async {
    final current = ++requestId;
    final now = DateTime.now();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await (widget.loadPlan ??
              (service ??= WorkforcePlanningService()).load)(
          employerId: widget.employerId,
          window: _window(now),
          now: now,
          siteId: siteId,
          tradeId: tradeId);
      if (!mounted || current != requestId) return;
      setState(() {
        plan = result;
        loading = false;
      });
    } catch (_) {
      if (!mounted || current != requestId) return;
      setState(() {
        loading = false;
        error = 'Could not load workforce planning. Please retry.';
      });
    }
  }

  Future<void> _chooseCustomRange() async {
    final now = DateTime.now();
    final choice = await showDateRangePicker(
        context: context,
        firstDate: now.subtract(const Duration(days: 365)),
        lastDate: now.add(const Duration(days: 730)),
        initialDateRange: customRange ??
            DateTimeRange(start: now, end: now.add(const Duration(days: 14))));
    if (choice == null || !mounted) return;
    setState(() {
      customRange = choice;
      horizon = _Horizon.custom;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) => WebPageContainer(
        child: ListView(children: [
          Row(children: [
            const Expanded(
                child: Text('Workforce',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
            IconButton(
                tooltip: 'Refresh planning',
                onPressed: _load,
                icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 10),
          _filters(),
          const SizedBox(height: 16),
          if (loading && plan == null)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator())),
          if (loading && plan != null) const LinearProgressIndicator(),
          if (error != null)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(child: Text(error!)),
                  TextButton(onPressed: _load, child: const Text('Retry'))
                ])),
          if (plan case final value?) ...[
            _metrics(value),
            const SizedBox(height: 24),
            _sectionTitle('Sites', Icons.location_city_outlined),
            _siteRows(value),
            const SizedBox(height: 20),
            _sectionTitle('Trades', Icons.handyman_outlined),
            _tradeRows(value),
            const SizedBox(height: 20),
            _sectionTitle('Staffing gaps', Icons.person_search_outlined),
            _gapRows(value),
            const SizedBox(height: 20),
            _sectionTitle('Starts & finishes', Icons.event_outlined),
            _changeRows(value),
            const SizedBox(height: 20),
            _sectionTitle('Assignment conflicts', Icons.warning_amber_outlined),
            _conflictRows(value),
            const SizedBox(height: 20),
            _sectionTitle('Assignments by site', Icons.groups_outlined),
            _assignmentRows(value),
          ],
        ]),
      );

  Widget _filters() {
    final sites = plan?.sites ?? [];
    final selectedSite = siteId == ''
        ? '_legacy'
        : siteId == null || sites.any((site) => site.id == siteId)
            ? siteId
            : null;
    return Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                key: ValueKey('workforce-site:${selectedSite ?? ''}'),
                isExpanded: true,
                initialValue: selectedSite ?? '',
                decoration: const InputDecoration(
                    labelText: 'Site',
                    isDense: true,
                    border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All Sites')),
                  const DropdownMenuItem(
                      value: '_legacy', child: Text('No Site / Legacy')),
                  for (final site in sites)
                    DropdownMenuItem(
                        value: site.id,
                        child: Text(site.name, overflow: TextOverflow.ellipsis))
                ],
                onChanged: (value) {
                  setState(() => siteId = value == ''
                      ? null
                      : value == '_legacy'
                          ? ''
                          : value);
                  _load();
                },
              )),
          SizedBox(
              width: 220,
              child: Autocomplete<String>(
                key: ValueKey('workforce-trade:${tradeId ?? ''}'),
                initialValue: TextEditingValue(
                    text: tradeId == null
                        ? ''
                        : JobTaxonomyService.roleFor(tradeId!)?.canonical ??
                            ''),
                optionsBuilder: (value) {
                  if (value.text.trim().isEmpty) {
                    return const Iterable<String>.empty();
                  }
                  return JobTaxonomyService.suggestions(value.text)
                      .take(8)
                      .map((role) => role.canonical);
                },
                onSelected: (name) {
                  setState(
                      () => tradeId = JobTaxonomyService.roleFor(name)?.id);
                  _load();
                },
                fieldViewBuilder: (_, controller, focusNode, onSubmit) =>
                    TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                            labelText: 'Trade',
                            isDense: true,
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                                tooltip: 'All trades',
                                onPressed: () {
                                  controller.clear();
                                  setState(() => tradeId = null);
                                  _load();
                                },
                                icon: const Icon(Icons.close))),
                        onSubmitted: (_) {
                          setState(() => tradeId =
                              JobTaxonomyService.bestRoleFor(controller.text)
                                  ?.id);
                          _load();
                        }),
              )),
          SegmentedButton<_Horizon>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Horizon.week, label: Text('This week')),
                ButtonSegment(value: _Horizon.twoWeeks, label: Text('2 weeks')),
                ButtonSegment(
                    value: _Horizon.fourWeeks, label: Text('4 weeks')),
                ButtonSegment(value: _Horizon.custom, label: Text('Custom')),
              ],
              selected: {horizon},
              onSelectionChanged: (values) {
                if (values.first == _Horizon.custom) {
                  _chooseCustomRange();
                  return;
                }
                setState(() => horizon = values.first);
                _load();
              }),
          if (horizon == _Horizon.custom && customRange != null)
            TextButton(
                onPressed: _chooseCustomRange,
                child: Text(
                    '${_date(customRange!.start)} – ${_date(customRange!.end)}')),
        ]);
  }

  Widget _metrics(WorkforcePlan data) =>
      Wrap(spacing: 10, runSpacing: 10, children: [
        _metric('Active Sites', data.activeSites, Icons.location_city_outlined),
        _metric('Active Workers', data.activeWorkers, Icons.groups_outlined),
        _metric(
            'Starting This Week', data.startingThisWeek, Icons.login_outlined),
        _metric('Finishing This Week', data.finishingThisWeek,
            Icons.logout_outlined),
        _metric('Open Vacancies', data.openVacancies, Icons.work_outline),
        _metric('Staffing Gaps', data.gapCount, Icons.person_search_outlined),
        _metric('Assignment Conflicts', data.conflicts.length,
            Icons.warning_amber_outlined),
        _metric('Projected Workers', data.projectedAtRangeEnd,
            Icons.timeline_outlined),
      ]);

  Widget _metric(String label, int value, IconData icon) => Container(
      width: 190,
      height: 96,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD9E2E7)),
          borderRadius: BorderRadius.circular(6)),
      child: Row(children: [
        Icon(icon, color: WebTheme.accent),
        const SizedBox(width: 10),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text('$value',
                  style: const TextStyle(
                      fontSize: 23, fontWeight: FontWeight.w700)),
              Text(label, maxLines: 2, style: const TextStyle(fontSize: 12))
            ]))
      ]));

  Widget _sectionTitle(String label, IconData icon) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))
      ]));

  Widget _siteRows(WorkforcePlan data) {
    if (data.siteSummaries.isEmpty) {
      return _empty('No Sites in this selection.');
    }
    return Column(children: [
      for (final row in data.siteSummaries)
        _row(
            title: row.name,
            subtitle: [row.city, row.region]
                .where((item) => item.isNotEmpty)
                .join(', '),
            details:
                '${row.currentWorkers} working  ·  ${row.starting} starting  ·  '
                '${row.finishing} finishing  ·  ${row.openVacancies} vacancies  ·  '
                '${row.openPositions} open positions',
            actions: [
              if (row.siteId.isNotEmpty && widget.onOpenSite != null)
                TextButton(
                    onPressed: () => widget.onOpenSite!(row.siteId),
                    child: const Text('Open Site')),
              if (row.siteId.isNotEmpty && widget.onOpenCalendar != null)
                IconButton(
                    tooltip: 'View in Calendar',
                    onPressed: () => widget.onOpenCalendar!(row.siteId),
                    icon: const Icon(Icons.calendar_month_outlined)),
            ])
    ]);
  }

  Widget _tradeRows(WorkforcePlan data) {
    if (data.tradeSummaries.isEmpty) {
      return _empty('No trades in this selection.');
    }
    return Column(children: [
      for (final row in data.tradeSummaries)
        _row(
            title: row.tradeName,
            details:
                '${row.currentWorkers} working  ·  ${row.starting} starting  ·  '
                '${row.finishing} finishing  ·  ${row.openPositions} open positions  ·  '
                '${row.projectedWorkers} projected')
    ]);
  }

  Widget _gapRows(WorkforcePlan data) {
    if (data.gaps.isEmpty) {
      return _empty('No open vacancy positions in this period.');
    }
    return Column(children: [
      for (final gap in data.gaps)
        _row(
            title: '${gap.tradeName} · ${_siteName(data, gap.siteId)}',
            details:
                '${gap.gapCount} to fill  ·  ${gap.currentWorkers} working  ·  '
                '${gap.starting} starting  ·  ${gap.finishing} finishing  ·  '
                'needed ${_date(gap.needDate)}',
            actions: [
              if (widget.onFindWorkers != null)
                FilledButton.icon(
                    onPressed: () {
                      widget.onFindWorkers!(
                          WorkforceTalentRequest.fromGap(data, gap));
                    },
                    icon: const Icon(Icons.person_search_outlined, size: 18),
                    label: const Text('Find Workers')),
              if (widget.onOpenJob != null)
                TextButton(
                    onPressed: () => widget.onOpenJob!(gap.vacancies.first.id),
                    child: const Text('Open Vacancy')),
            ])
    ]);
  }

  Widget _changeRows(WorkforcePlan data) {
    final changes = <({PlanningChange value, bool starting})>[
      for (final start in data.starts) (value: start, starting: true),
      for (final finish in data.finishes) (value: finish, starting: false),
    ]..sort((a, b) => a.value.date.compareTo(b.value.date));
    if (changes.isEmpty) return _empty('No starts or finishes in this period.');
    return Column(children: [
      for (final change in changes.take(40))
        _row(
            title: '${change.starting ? 'Starts' : 'Finishes'} · '
                '${_workerName(change.value.assignment.data)}',
            subtitle: '${change.value.assignment.tradeName} · '
                '${change.value.assignment.siteName}',
            details: _date(change.value.date),
            actions: [
              if (widget.onOpenSite != null &&
                  (change.value.assignment.data['siteId'] ?? '')
                      .toString()
                      .isNotEmpty)
                TextButton(
                    onPressed: () => widget.onOpenSite!(
                        change.value.assignment.data['siteId'].toString()),
                    child: const Text('Site')),
            ])
    ]);
  }

  Widget _conflictRows(WorkforcePlan data) {
    if (data.conflicts.isEmpty) return _empty('No overlapping assignments.');
    return Column(children: [
      for (final conflict in data.conflicts)
        _row(
            title: 'Warning · ${conflict.workerName}',
            subtitle:
                '${conflict.first.siteName} and ${conflict.second.siteName}',
            details: 'Overlap ${_date(conflict.overlapStart)} – '
                '${_date(conflict.overlapEnd)}')
    ]);
  }

  Widget _assignmentRows(WorkforcePlan data) {
    if (data.assignments.isEmpty) {
      return _empty('No assignments in this period.');
    }
    final sorted = [...data.assignments]
      ..sort((a, b) => a.siteName.compareTo(b.siteName));
    return Column(children: [
      for (final assignment in sorted.take(60))
        _row(
            title: _workerName(assignment.data),
            subtitle: '${assignment.siteName} · ${assignment.tradeName}',
            details: '${assignment.status}  ·  '
                '${assignment.startDate == null ? 'Start not set' : _date(assignment.startDate!)}'
                ' – ${assignment.actualEndDate == null && assignment.expectedEndDate == null ? 'Ongoing' : _date(assignment.actualEndDate ?? assignment.expectedEndDate!)}',
            actions: [
              if (widget.onOpenJob != null && assignment.vacancyId.isNotEmpty)
                TextButton(
                    onPressed: () => widget.onOpenJob!(assignment.vacancyId),
                    child: const Text('Vacancy'))
            ])
    ]);
  }

  Widget _row(
          {required String title,
          String subtitle = '',
          required String details,
          List<Widget> actions = const []}) =>
      Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFD9E2E7)),
              borderRadius: BorderRadius.circular(6)),
          child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          if (subtitle.isNotEmpty) Text(subtitle),
                          Text(details,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF607481)))
                        ])),
                if (actions.isNotEmpty) Wrap(spacing: 4, children: actions),
              ]));

  Widget _empty(String message) => Padding(
      padding: const EdgeInsets.all(16),
      child: Text(message, style: const TextStyle(color: Color(0xFF607481))));

  String _siteName(WorkforcePlan data, String id) =>
      data.sites.where((site) => site.id == id).firstOrNull?.name ??
      'No Site / Legacy';

  String _workerName(Map<String, dynamic> data) =>
      (data['workerDisplayName'] ?? 'Worker').toString();

  String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';
}

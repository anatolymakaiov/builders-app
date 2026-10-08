import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../services/operational_calendar.dart';
import '../../../services/calendar_export.dart';
import '../../../services/worker_assignment_service.dart';
import '../../../services/site_event_service.dart';
import 'web_site_event_dialog.dart';
import '../../services/web_calendar_download_stub.dart'
    if (dart.library.js_interop) '../../services/web_calendar_download.dart';
import '../../services/web_sites_service.dart';
import '../../theme/web_theme.dart';
import '../../widgets/web_page_container.dart';

enum CalendarView { month, week, day }

class WebCalendarPage extends StatefulWidget {
  const WebCalendarPage(
      {super.key,
      required this.uid,
      required this.employer,
      this.initialSiteId,
      this.initialDate,
      this.onOpenJob,
      this.onOpenSite,
      this.refreshToken = 0,
      this.loadEvents,
      this.loadCurrentNext,
      this.loadExport,
      this.loadSingleAssignment,
      this.downloadIcs,
      this.employerSites});

  final String uid;
  final bool employer;
  final String? initialSiteId;
  final DateTime? initialDate;
  final ValueChanged<String>? onOpenJob;
  final ValueChanged<String>? onOpenSite;
  final int refreshToken;
  final Future<List<CalendarEvent>> Function(CalendarRange)? loadEvents;
  final Future<List<WorkerAssignment>> Function()? loadCurrentNext;
  final Future<List<CalendarExportEvent>> Function(CalendarRange, String?)?
      loadExport;
  final Future<CalendarExportEvent?> Function(String, CalendarRange)?
      loadSingleAssignment;
  final void Function(String, String)? downloadIcs;
  final Stream<List<WebSite>>? employerSites;

  @override
  State<WebCalendarPage> createState() => _WebCalendarPageState();
}

class _WebCalendarPageState extends State<WebCalendarPage> {
  late final service = OperationalCalendarService();
  late Future<List<CalendarEvent>> events;
  late Future<List<WorkerAssignment>> currentNext;
  late Stream<List<WebSite>> sites;
  DateTime selectedDay = DateTime.now();
  CalendarView view = CalendarView.month;
  String? siteId;
  bool exporting = false;
  late final siteEventService = SiteEventService();

  @override
  void initState() {
    super.initState();
    siteId = widget.initialSiteId;
    selectedDay = widget.initialDate ?? DateTime.now();
    sites = widget.employerSites ??
        (widget.employer
            ? WebSitesService().watchEmployerSites(widget.uid)
            : const Stream<List<WebSite>>.empty());
    _load();
    if (!widget.employer) _loadCurrentNext();
  }

  @override
  void didUpdateWidget(covariant WebCalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid || oldWidget.employer != widget.employer) {
      siteId = widget.initialSiteId;
      selectedDay = widget.initialDate ?? DateTime.now();
      sites = widget.employerSites ??
          (widget.employer
              ? WebSitesService().watchEmployerSites(widget.uid)
              : const Stream<List<WebSite>>.empty());
      _load();
      if (!widget.employer) _loadCurrentNext();
    } else if (oldWidget.initialSiteId != widget.initialSiteId) {
      siteId = widget.initialSiteId;
    }
    if (oldWidget.initialDate != widget.initialDate &&
        widget.initialDate != null) {
      selectedDay = widget.initialDate!;
    }
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
      if (!widget.employer) _loadCurrentNext();
    }
  }

  CalendarRange get range => switch (view) {
        CalendarView.month => CalendarRange.month(selectedDay),
        CalendarView.week => CalendarRange.week(selectedDay),
        CalendarView.day => CalendarRange.day(selectedDay),
      };

  void _load() {
    events = widget.loadEvents?.call(range) ??
        service.load(uid: widget.uid, employer: widget.employer, range: range);
  }

  void _loadCurrentNext() => currentNext =
      widget.loadCurrentNext?.call() ?? service.loadCurrentNext(widget.uid);

  void _changeView(CalendarView next) => setState(() {
        view = next;
        _load();
      });

  void _move(int step) => setState(() {
        selectedDay = switch (view) {
          CalendarView.month => DateTime(selectedDay.year,
              selectedDay.month + step, selectedDay.day.clamp(1, 28)),
          CalendarView.week => selectedDay.add(Duration(days: 7 * step)),
          CalendarView.day => selectedDay.add(Duration(days: step)),
        };
        _load();
      });

  String _date(DateTime date) =>
      MaterialLocalizations.of(context).formatMediumDate(date);

  Future<void> _export({String? selectedSite, bool allSites = false}) async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final exportRange = range;
      final exportSite = allSites ? null : (selectedSite ?? siteId);
      final data = await (widget.loadExport?.call(exportRange, exportSite) ??
          service.loadExport(
              uid: widget.uid,
              employer: widget.employer,
              range: exportRange,
              siteId: exportSite));
      if (!mounted) return;
      final labelDate =
          view == CalendarView.month ? selectedDay : exportRange.start;
      final filename =
          'stroyka-${widget.employer ? 'employer' : 'worker'}-calendar-'
          '${labelDate.year}-${labelDate.month.toString().padLeft(2, '0')}.ics';
      (widget.downloadIcs ?? downloadCalendarIcs)(
          const IcsCalendarProvider().exportEvents(data), filename);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Calendar downloaded')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not export calendar. Try again.')));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  void _exportSingle(WorkerAssignment assignment) {
    final start = assignment.startDate;
    if (start == null) return;
    final event = assignmentExportEvent(assignment.id, assignment.data,
        uid: widget.uid, employer: false, range: CalendarRange.day(start));
    if (event == null) return;
    (widget.downloadIcs ?? downloadCalendarIcs)(
        const IcsCalendarProvider().singleEvent(event),
        'assignment-${assignment.id}.ics');
  }

  Future<void> _exportSelected(CalendarEvent selected) async {
    try {
      final event = await (widget.loadSingleAssignment
              ?.call(selected.sourceId, CalendarRange.day(selected.date)) ??
          service.loadSingleAssignmentExport(
              workerId: widget.uid,
              assignmentId: selected.sourceId,
              range: CalendarRange.day(selected.date)));
      if (!mounted || event == null) return;
      (widget.downloadIcs ?? downloadCalendarIcs)(
          const IcsCalendarProvider().singleEvent(event),
          'assignment-${event.sourceId}.ics');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not add assignment to calendar.')));
      }
    }
  }

  Future<void> _editSiteEvent([SiteEvent? initial]) async {
    try {
      final availableSites =
          await WebSitesService().loadEmployerSites(widget.uid);
      if (!mounted) return;
      final draft = await showDialog<SiteEventDraft>(
          context: context,
          builder: (_) => WebSiteEventDialog(
              sites: availableSites,
              initial: initial,
              initialSiteId: siteId,
              initialDate: selectedDay));
      if (draft == null) return;
      if (initial == null) {
        await siteEventService.create(widget.uid,
            title: draft.title,
            type: draft.type,
            start: draft.start,
            end: draft.end,
            allDay: draft.allDay,
            siteId: draft.siteId,
            description: draft.description,
            reminderOffsetsMinutes: draft.reminderOffsetsMinutes);
      } else {
        await siteEventService.update(widget.uid, initial,
            title: draft.title,
            type: draft.type,
            start: draft.start,
            end: draft.end,
            allDay: draft.allDay,
            siteId: draft.siteId,
            description: draft.description,
            reminderOffsetsMinutes: draft.reminderOffsetsMinutes);
      }
      if (mounted) setState(_load);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Could not save event. Check the site and try again.')));
      }
    }
  }

  Future<void> _openManualEvent(CalendarEvent event) async {
    try {
      final current = await siteEventService.getOwn(widget.uid, event.sourceId);
      if (!mounted) return;
      if (current == null) {
        setState(_load);
        return;
      }
      final availableSites = current.siteId.isEmpty
          ? <WebSite>[]
          : await WebSitesService().loadEmployerSites(widget.uid);
      if (!mounted) return;
      final siteName = availableSites
          .where((site) => site.id == current.siteId)
          .map((site) => site.name)
          .firstOrNull;
      final action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(current.title),
                content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(siteEventTypes[current.type] ?? 'Site event'),
                        Text(siteName ?? 'Company-wide event'),
                        Text(current.allDay
                            ? _date(current.start!)
                            : '${_date(current.start!)} · ${TimeOfDay.fromDateTime(current.start!).format(context)}'),
                        if (current.end != null)
                          Text('Ends ${_date(current.end!)}'),
                        if (current.description.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(current.description),
                        ],
                      ],
                    )),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close')),
                  if (siteName != null && widget.onOpenSite != null)
                    TextButton(
                        onPressed: () => Navigator.pop(context, 'site'),
                        child: const Text('Open Site')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, 'delete'),
                      child: const Text('Delete')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, 'edit'),
                      child: const Text('Edit')),
                ],
              ));
      if (!mounted) return;
      if (action == 'edit') {
        await _editSiteEvent(current);
      } else if (action == 'site') {
        widget.onOpenSite?.call(current.siteId);
      } else if (action == 'delete') {
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text('Delete event?'),
                  content: Text('Delete “${current.title}”?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete')),
                  ],
                ));
        if (confirmed == true) {
          await siteEventService.delete(widget.uid, current);
          if (mounted) setState(_load);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not load or update event. Try again.')));
      }
    }
  }

  Future<void> _editAssignmentReminders(CalendarEvent event) async {
    try {
      final functions = FirebaseFunctions.instance;
      final response = await functions
          .httpsCallable('getAssignmentReminderPreferences')
          .call<Map<String, dynamic>>({'assignmentId': event.sourceId});
      if (!mounted) return;
      final start = (response.data['startOffsets'] as List<dynamic>)
          .whereType<int>()
          .toSet();
      final finish = (response.data['finishOffsets'] as List<dynamic>)
          .whereType<int>()
          .toSet();
      final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, update) {
          Widget choices(String label, Set<int> offsets) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleSmall),
                  Wrap(spacing: 8, children: [
                    for (final choice in siteReminderChoices.entries)
                      FilterChip(
                        label: Text(choice.value),
                        selected: offsets.contains(choice.key),
                        onSelected: (selected) => update(() {
                          if (selected) {
                            offsets.add(choice.key);
                          } else {
                            offsets.remove(choice.key);
                          }
                        }),
                      ),
                  ]),
                ],
              );
          return AlertDialog(
            title: const Text('Assignment reminders'),
            content: SizedBox(
              width: 430,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                choices('Worker start', start),
                const SizedBox(height: 12),
                choices('Expected finish', finish),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save')),
            ],
          );
        }),
      );
      if (save != true) return;
      await functions.httpsCallable('setAssignmentReminderPreferences').call({
        'assignmentId': event.sourceId,
        'startOffsets': start.toList()..sort(),
        'finishOffsets': finish.toList()..sort(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Assignment reminders updated.'),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not update assignment reminders.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) => WebPageContainer(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Calendar',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<CalendarView>(
                segments: [
                  const ButtonSegment(
                      value: CalendarView.month, label: Text('Month')),
                  if (widget.employer)
                    const ButtonSegment(
                        value: CalendarView.week, label: Text('Week')),
                  const ButtonSegment(
                      value: CalendarView.day, label: Text('Day')),
                ],
                selected: {view},
                onSelectionChanged: (selection) => _changeView(selection.first),
              ),
              if (widget.employer)
                FilledButton.icon(
                    onPressed: () => _editSiteEvent(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add event')),
              if (widget.employer)
                SizedBox(
                    width: 230,
                    child: StreamBuilder<List<WebSite>>(
                      stream: sites,
                      builder: (context, snapshot) =>
                          DropdownButtonFormField<String>(
                        key: ValueKey('site-filter:${siteId ?? 'all'}'),
                        isExpanded: true,
                        initialValue: siteId,
                        decoration: const InputDecoration(labelText: 'Site'),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('All Sites')),
                          const DropdownMenuItem(
                              value: '', child: Text('No Site / Legacy')),
                          if (siteId != null &&
                              siteId!.isNotEmpty &&
                              !(snapshot.data ?? const <WebSite>[])
                                  .any((site) => site.id == siteId))
                            DropdownMenuItem(
                                value: siteId,
                                child: const Text('Selected site')),
                          for (final site in snapshot.data ?? const <WebSite>[])
                            DropdownMenuItem(
                                value: site.id,
                                child: Text(site.name,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (value) => setState(() => siteId = value),
                      ),
                    )),
              IconButton(
                  tooltip: 'Previous period',
                  onPressed: () => _move(-1),
                  icon: const Icon(Icons.chevron_left)),
              OutlinedButton(
                  onPressed: () => setState(() {
                        selectedDay = DateTime.now();
                        _load();
                      }),
                  child: const Text('Today')),
              IconButton(
                tooltip: 'Refresh calendar',
                onPressed: () => setState(() {
                  _load();
                  if (!widget.employer) _loadCurrentNext();
                }),
                icon: const Icon(Icons.refresh),
              ),
              if (widget.employer)
                PopupMenuButton<String>(
                  tooltip: 'Export calendar',
                  enabled: !exporting,
                  onSelected: (value) => _export(
                      selectedSite: value == 'site' ? siteId : null,
                      allSites: value == 'all'),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'visible', child: Text('Export visible period')),
                    if (siteId != null)
                      const PopupMenuItem(
                          value: 'site', child: Text('Export selected site')),
                    const PopupMenuItem(
                        value: 'all', child: Text('Export all sites')),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: WebTheme.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.download_outlined, size: 19),
                      SizedBox(width: 7),
                      Text('Export'),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, size: 18),
                    ]),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: exporting ? null : () => _export(),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export visible period'),
                ),
              IconButton(
                  tooltip: 'Next period',
                  onPressed: () => _move(1),
                  icon: const Icon(Icons.chevron_right)),
              Text(
                  view == CalendarView.day
                      ? _date(selectedDay)
                      : view == CalendarView.week
                          ? '${_date(range.start)} – ${_date(range.end.subtract(const Duration(days: 1)))}'
                          : MaterialLocalizations.of(context)
                              .formatMonthYear(selectedDay),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          if (!widget.employer)
            FutureBuilder<List<WorkerAssignment>>(
              future: currentNext,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return TextButton.icon(
                    onPressed: () => setState(_loadCurrentNext),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Could not load current work. Retry'),
                  );
                }
                if (!snapshot.hasData) return const SizedBox.shrink();
                final selection = currentOrNextAssignment(snapshot.data!);
                if (selection == null) return const SizedBox.shrink();
                final next = selection.assignment;
                return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      tileColor: WebTheme.accentSoft,
                      leading: const Icon(Icons.work_outline),
                      title: Text(selection.current
                          ? 'Current assignment'
                          : 'Next assignment'),
                      subtitle: Text([
                        next.siteName,
                        next.tradeName,
                        'Starts ${_date(next.startDate!)}',
                        if ((next.actualEndDate ?? next.expectedEndDate) !=
                            null)
                          'Finish ${_date((next.actualEndDate ?? next.expectedEndDate)!)}',
                      ].where((s) => s.isNotEmpty).join(' · ')),
                      trailing: IconButton(
                        tooltip: 'Add to Calendar',
                        icon: const Icon(Icons.event_available_outlined),
                        onPressed: () => _exportSingle(next),
                      ),
                      onTap: next.vacancyId.isEmpty
                          ? null
                          : () => widget.onOpenJob?.call(next.vacancyId),
                    ));
              },
            ),
          Expanded(
              child: FutureBuilder<List<CalendarEvent>>(
            future: events,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load calendar events.'),
                    TextButton(
                        onPressed: () => setState(_load),
                        child: const Text('Retry')),
                  ],
                ));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snapshot.data!;
              final filtered = filterCalendarEventsBySite(all, siteId);
              return SingleChildScrollView(
                  child: switch (view) {
                CalendarView.month => _month(filtered),
                CalendarView.week => _week(filtered),
                CalendarView.day => _agenda(filtered, selectedDay),
              });
            },
          )),
        ]),
      );

  Widget _month(List<CalendarEvent> events) {
    final days = range.end.difference(range.start).inDays;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final row in [for (var i = 0; i < days; i += 7) i])
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var offset = 0; offset < 7; offset++)
            Expanded(
                child: _dayCell(
                    range.start.add(Duration(days: row + offset)), events)),
        ]),
      const SizedBox(height: 16),
      Text(_date(selectedDay),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      _agenda(events, selectedDay),
    ]);
  }

  Widget _dayCell(DateTime date, List<CalendarEvent> events) {
    final onDay = events
        .where((event) => CalendarRange.day(date).contains(event.date))
        .toList();
    final selected = CalendarRange.day(date).contains(selectedDay);
    return InkWell(
      key: ValueKey('calendar-day:${date.toIso8601String()}'),
      onTap: () => setState(() {
        final changedMonth =
            selectedDay.year != date.year || selectedDay.month != date.month;
        selectedDay = date;
        if (changedMonth) _load();
      }),
      child: Container(
        height: 86,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: selected ? WebTheme.accentSoft : WebTheme.surface,
          border: Border.all(color: WebTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${date.day}',
              style: TextStyle(
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          if (onDay.isNotEmpty)
            Text('${onDay.length} event${onDay.length == 1 ? '' : 's'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: WebTheme.accent, fontSize: 11)),
          if (onDay.isNotEmpty)
            Text(onDay.first.typeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
          if (onDay.length > 1)
            Text('+${onDay.length - 1} more',
                style: const TextStyle(fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _week(List<CalendarEvent> events) => Column(children: [
        for (var day = range.start;
            day.isBefore(range.end);
            day = DateTime(day.year, day.month, day.day + 1))
          Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(MaterialLocalizations.of(context).formatFullDate(day),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  _agenda(events, day),
                ],
              )),
      ]);

  Widget _agenda(List<CalendarEvent> events, DateTime day) {
    final onDay = events
        .where((event) => CalendarRange.day(day).contains(event.date))
        .toList();
    if (onDay.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(widget.employer
            ? 'No events in this period'
            : 'No scheduled work in this period'),
      );
    }
    return Column(children: [
      for (final event in onDay)
        ListTile(
          leading: Icon(
              switch (event.type) {
                CalendarEventType.vacancyStart => Icons.work_outline,
                CalendarEventType.assignmentStart => Icons.play_arrow,
                CalendarEventType.assignmentOngoing =>
                  Icons.work_history_outlined,
                CalendarEventType.assignmentFinish => Icons.flag_outlined,
                CalendarEventType.unavailable => Icons.event_busy_outlined,
                CalendarEventType.siteStart => Icons.flag_outlined,
                CalendarEventType.siteFinish => Icons.flag_outlined,
                CalendarEventType.manual => Icons.event_outlined,
              },
              color: WebTheme.accent),
          title: Text('${event.typeLabel}: ${event.title}'),
          subtitle: Text([
            if (event.type == CalendarEventType.manual && !event.allDay)
              TimeOfDay.fromDateTime(event.date).format(context),
            event.siteName,
            event.trade,
            if (event.type == CalendarEventType.manual)
              siteEventTypes[event.eventType] ?? 'Other',
          ].where((part) => part.isNotEmpty).toSet().join(' · ')),
          trailing: !widget.employer &&
                  {
                    CalendarEventType.assignmentStart,
                    CalendarEventType.assignmentOngoing,
                    CalendarEventType.assignmentFinish
                  }.contains(event.type)
              ? IconButton(
                  tooltip: 'Add to Calendar',
                  icon: const Icon(Icons.event_available_outlined),
                  onPressed: () => _exportSelected(event),
                )
              : event.vacancyId.isNotEmpty || event.siteId.isNotEmpty
                  ? const Icon(Icons.chevron_right)
                  : null,
          onTap: () {
            if (widget.employer && event.type == CalendarEventType.manual) {
              _openManualEvent(event);
            } else if (widget.employer &&
                {
                  CalendarEventType.assignmentStart,
                  CalendarEventType.assignmentFinish
                }.contains(event.type)) {
              _editAssignmentReminders(event);
            } else if (widget.employer &&
                event.type != CalendarEventType.vacancyStart &&
                event.siteId.isNotEmpty &&
                widget.onOpenSite != null) {
              widget.onOpenSite!(event.siteId);
            } else if (event.vacancyId.isNotEmpty) {
              widget.onOpenJob?.call(event.vacancyId);
            }
          },
        ),
    ]);
  }
}

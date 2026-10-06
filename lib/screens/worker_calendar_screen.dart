import 'package:flutter/material.dart';
import 'package:add_2_calendar/add_2_calendar.dart';

import '../services/calendar_export.dart';
import '../services/operational_calendar.dart';
import '../services/worker_assignment_service.dart';

class WorkerCalendarScreen extends StatefulWidget {
  const WorkerCalendarScreen(
      {super.key,
      required this.workerId,
      this.loadEvents,
      this.loadCurrentNext,
      this.loadSingleAssignment,
      this.addToCalendar});

  final String workerId;
  final Future<List<CalendarEvent>> Function(CalendarRange)? loadEvents;
  final Future<List<WorkerAssignment>> Function()? loadCurrentNext;
  final Future<CalendarExportEvent?> Function(String, CalendarRange)?
      loadSingleAssignment;
  final Future<bool> Function(CalendarExportEvent)? addToCalendar;

  @override
  State<WorkerCalendarScreen> createState() => _WorkerCalendarScreenState();
}

class _WorkerCalendarScreenState extends State<WorkerCalendarScreen> {
  late final service = OperationalCalendarService();
  late Future<List<CalendarEvent>> events;
  late Future<List<WorkerAssignment>> assignments;
  DateTime selected = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    assignments = widget.loadCurrentNext?.call() ??
        service.loadCurrentNext(widget.workerId);
  }

  void _load() => events =
      widget.loadEvents?.call(CalendarRange.month(selected)) ??
          service.load(
              uid: widget.workerId,
              employer: false,
              range: CalendarRange.month(selected));

  void _move(int delta) => setState(() {
        selected = DateTime(selected.year, selected.month + delta, 1);
        _load();
      });

  String _date(DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value);

  Future<void> _addAssignment(WorkerAssignment assignment) async {
    final start = assignment.startDate;
    if (start == null) return;
    final event = assignmentExportEvent(assignment.id, assignment.data,
        uid: widget.workerId, employer: false, range: CalendarRange.day(start));
    if (event == null) return;
    await _addExportEvent(event);
  }

  Future<void> _addSelected(CalendarEvent selectedEvent) async {
    try {
      final event = await (widget.loadSingleAssignment?.call(
              selectedEvent.sourceId, CalendarRange.day(selectedEvent.date)) ??
          service.loadSingleAssignmentExport(
              workerId: widget.workerId,
              assignmentId: selectedEvent.sourceId,
              range: CalendarRange.day(selectedEvent.date)));
      if (event != null && mounted) await _addExportEvent(event);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not add assignment to calendar.')));
      }
    }
  }

  Future<void> _addExportEvent(CalendarExportEvent event) async {
    final start = event.start;
    final last = event.end ?? event.start;
    final end = DateTime(last.year, last.month, last.day + 1);
    try {
      final added = await (widget.addToCalendar?.call(event) ??
          Add2Calendar.addEvent2Cal(Event(
            title: event.title,
            description: event.description,
            location: event.location,
            startDate: DateTime(start.year, start.month, start.day),
            endDate: end,
            allDay: true,
          )));
      if (mounted && !added) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open the calendar. Try again.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open the calendar. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = CalendarRange.month(selected);
    final dayCount = range.end.difference(range.start).inDays;
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: SafeArea(
          child: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _load();
            assignments = widget.loadCurrentNext?.call() ??
                service.loadCurrentNext(widget.workerId);
          });
          await events;
        },
        child: ListView(padding: const EdgeInsets.all(16), children: [
          FutureBuilder<List<WorkerAssignment>>(
            future: assignments,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return TextButton.icon(
                  onPressed: () => setState(() => assignments =
                      widget.loadCurrentNext?.call() ??
                          service.loadCurrentNext(widget.workerId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Could not load current work. Retry'),
                );
              }
              final data = snapshot.data ?? const <WorkerAssignment>[];
              final selection = currentOrNextAssignment(data);
              if (selection == null) return const SizedBox.shrink();
              final next = selection.assignment;
              return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    leading: const Icon(Icons.work_outline),
                    title: Text(selection.current
                        ? 'Current assignment'
                        : 'Next assignment'),
                    subtitle: Text([
                      next.siteName,
                      next.tradeName,
                      'Starts ${_date(next.startDate!)}',
                      if ((next.actualEndDate ?? next.expectedEndDate) != null)
                        'Finish ${_date((next.actualEndDate ?? next.expectedEndDate)!)}',
                    ].where((s) => s.isNotEmpty).join(' · ')),
                    trailing: IconButton(
                      tooltip: 'Add to Calendar',
                      icon: const Icon(Icons.event_available_outlined),
                      onPressed: () => _addAssignment(next),
                    ),
                  ));
            },
          ),
          Row(children: [
            IconButton(
                tooltip: 'Previous month',
                onPressed: () => _move(-1),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
                child: Center(
                    child: Text(
                        MaterialLocalizations.of(context)
                            .formatMonthYear(selected),
                        style: Theme.of(context).textTheme.titleMedium))),
            IconButton(
                tooltip: 'Next month',
                onPressed: () => _move(1),
                icon: const Icon(Icons.chevron_right)),
          ]),
          TextButton(
              onPressed: () => setState(() {
                    selected = DateTime.now();
                    _load();
                  }),
              child: const Text('Today')),
          FutureBuilder<List<CalendarEvent>>(
            future: events,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(children: [
                  const Text('Could not load calendar events.'),
                  TextButton(
                      onPressed: () => setState(_load),
                      child: const Text('Retry')),
                ]);
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: dayCount,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7, mainAxisExtent: 54),
                    itemBuilder: (context, index) {
                      final date = range.start.add(Duration(days: index));
                      final count = all
                          .where((event) =>
                              CalendarRange.day(date).contains(event.date))
                          .length;
                      final isSelected =
                          CalendarRange.day(date).contains(selected);
                      return InkWell(
                        onTap: () => setState(() {
                          final changedMonth = selected.year != date.year ||
                              selected.month != date.month;
                          selected = date;
                          if (changedMonth) _load();
                        }),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant),
                          ),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${date.day}'),
                                if (count > 0)
                                  Text('$count',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall),
                              ]),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(_date(selected),
                      style: Theme.of(context).textTheme.titleMedium),
                  ...all
                      .where((event) =>
                          CalendarRange.day(selected).contains(event.date))
                      .map((event) => ListTile(
                            leading: Icon(switch (event.type) {
                              CalendarEventType.assignmentStart =>
                                Icons.play_arrow,
                              CalendarEventType.assignmentOngoing =>
                                Icons.work_history_outlined,
                              CalendarEventType.assignmentFinish =>
                                Icons.flag_outlined,
                              CalendarEventType.vacancyStart =>
                                Icons.work_outline,
                              CalendarEventType.unavailable =>
                                Icons.event_busy_outlined,
                            }),
                            title: Text('${event.typeLabel}: ${event.title}'),
                            subtitle: Text([event.siteName, event.trade]
                                .where((s) => s.isNotEmpty)
                                .toSet()
                                .join(' · ')),
                            trailing: {
                              CalendarEventType.assignmentStart,
                              CalendarEventType.assignmentOngoing,
                              CalendarEventType.assignmentFinish,
                            }.contains(event.type)
                                ? IconButton(
                                    tooltip: 'Add to Calendar',
                                    icon: const Icon(
                                        Icons.event_available_outlined),
                                    onPressed: () => _addSelected(event),
                                  )
                                : null,
                          )),
                  if (!all.any((event) =>
                      CalendarRange.day(selected).contains(event.date)))
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No scheduled work in this period')),
                ],
              );
            },
          ),
        ]),
      )),
    );
  }
}

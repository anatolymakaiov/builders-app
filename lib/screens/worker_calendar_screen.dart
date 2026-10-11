import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';

import '../services/calendar_export.dart';
import '../services/operational_calendar.dart';
import '../services/worker_assignment_service.dart';
import '../services/worker_personal_calendar_service.dart';
import '../widgets/mobile_calendar_view.dart';

class WorkerCalendarScreen extends StatefulWidget {
  const WorkerCalendarScreen({
    super.key,
    required this.workerId,
    this.initialDate,
    this.embedded = false,
    this.loadEvents,
    this.loadCurrentNext,
    this.loadSingleAssignment,
    this.addToCalendar,
  });

  final String workerId;
  final DateTime? initialDate;
  final bool embedded;
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
  late final personal = WorkerPersonalCalendarService();
  late Future<List<CalendarEvent>> events;
  late Future<List<WorkerAssignment>> assignments;
  DateTime selected = DateTime.now();

  @override
  void initState() {
    super.initState();
    selected = widget.initialDate ?? DateTime.now();
    _load();
    assignments = widget.loadCurrentNext?.call() ??
        service.loadCurrentNext(widget.workerId);
  }

  @override
  void didUpdateWidget(covariant WorkerCalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workerId != widget.workerId) {
      selected = widget.initialDate ?? DateTime.now();
      _load();
      assignments = widget.loadCurrentNext?.call() ??
          service.loadCurrentNext(widget.workerId);
    }
  }

  void _load() {
    events = widget.loadEvents?.call(CalendarRange.month(selected)) ??
        service.load(
            uid: widget.workerId,
            employer: false,
            range: CalendarRange.month(selected));
  }

  Future<void> _refresh() async {
    setState(() {
      _load();
      assignments = widget.loadCurrentNext?.call() ??
          service.loadCurrentNext(widget.workerId);
    });
    await events;
  }

  Future<void> _create(MobileCalendarDraft draft) async {
    try {
      await personal.create(widget.workerId,
          title: draft.title,
          start: draft.start,
          end: draft.end,
          reminder: draft.reminder,
          reminderOffsetsMinutes:
              draft.alertMinutes < 0 ? [] : [draft.alertMinutes],
          description: draft.notes);
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save calendar entry. Try again.')));
      }
    }
  }

  Future<void> _edit(CalendarEvent event, MobileCalendarDraft draft) async {
    if (!event.id.startsWith('personal:')) return;
    try {
      await personal.update(widget.workerId, event.sourceId,
          title: draft.title,
          start: draft.start,
          end: draft.end,
          reminder: draft.reminder,
          reminderOffsetsMinutes:
              draft.alertMinutes < 0 ? [] : [draft.alertMinutes],
          description: draft.notes);
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update calendar entry.')));
      }
    }
  }

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
      if (event != null) await _addExportEvent(event);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not add assignment to calendar.')));
      }
    }
  }

  Future<void> _addExportEvent(CalendarExportEvent event) async {
    try {
      final last = event.end ?? event.start;
      final added = await (widget.addToCalendar?.call(event) ??
          Add2Calendar.addEvent2Cal(Event(
            title: event.title,
            description: event.description,
            location: event.location,
            startDate:
                DateTime(event.start.year, event.start.month, event.start.day),
            endDate: DateTime(last.year, last.month, last.day + 1),
            allDay: true,
          )));
      if (!added && mounted) {
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

  Widget _currentAssignment() => FutureBuilder<List<WorkerAssignment>>(
        future: assignments,
        builder: (context, snapshot) {
          final selection = currentOrNextAssignment(
              snapshot.data ?? const <WorkerAssignment>[]);
          if (selection == null) return const SizedBox.shrink();
          final assignment = selection.assignment;
          return ListTile(
            leading: const Icon(Icons.work_outline, color: Colors.white),
            title: Text(
                selection.current ? 'Current assignment' : 'Next assignment',
                style: const TextStyle(color: Colors.white)),
            subtitle: Text(
                [assignment.siteName, assignment.tradeName]
                    .where((part) => part.isNotEmpty)
                    .join(' · '),
                style: const TextStyle(color: Colors.white70)),
            trailing: IconButton(
              tooltip: 'Add to Calendar',
              icon: const Icon(Icons.event_available_outlined,
                  color: Colors.white),
              onPressed: () => _addAssignment(assignment),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final calendar = MobileCalendarView(
      key: ValueKey('${widget.workerId}-${selected.year}-${selected.month}'),
      selected: selected,
      events: events,
      leading: _currentAssignment(),
      onSelect: (day) => setState(() {
        final monthChanged =
            day.month != selected.month || day.year != selected.year;
        selected = day;
        if (monthChanged) _load();
      }),
      onMove: (delta) => setState(() {
        selected = DateTime(selected.year, selected.month + delta, 1);
        _load();
      }),
      onRefresh: _refresh,
      onCreate: _create,
      onExportAssignment: _addSelected,
      onEditManual: _edit,
      canEditManual: (event) => event.id.startsWith('personal:'),
    );
    return widget.embedded
        ? calendar
        : Scaffold(
            backgroundColor: const Color(0xFF08293A),
            appBar: AppBar(title: const Text('Calendar')),
            body: SafeArea(child: calendar));
  }
}

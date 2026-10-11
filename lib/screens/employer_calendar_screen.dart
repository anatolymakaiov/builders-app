import 'package:flutter/material.dart';

import '../services/operational_calendar.dart';
import '../services/site_event_service.dart';
import '../widgets/mobile_calendar_view.dart';

class EmployerCalendarScreen extends StatefulWidget {
  const EmployerCalendarScreen({
    super.key,
    required this.employerId,
    this.initialDate,
    this.loadEvents,
    this.embedded = false,
  });

  final String employerId;
  final DateTime? initialDate;
  final Future<List<CalendarEvent>> Function(CalendarRange)? loadEvents;
  final bool embedded;

  @override
  State<EmployerCalendarScreen> createState() => _EmployerCalendarScreenState();
}

class _EmployerCalendarScreenState extends State<EmployerCalendarScreen> {
  late DateTime selected;
  late Future<List<CalendarEvent>> events;

  @override
  void initState() {
    super.initState();
    selected = widget.initialDate ?? DateTime.now();
    _load();
  }

  @override
  void didUpdateWidget(covariant EmployerCalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employerId != widget.employerId) {
      selected = widget.initialDate ?? DateTime.now();
      _load();
    }
  }

  void _load() {
    events = widget.loadEvents?.call(CalendarRange.month(selected)) ??
        OperationalCalendarService().load(
          uid: widget.employerId,
          employer: true,
          range: CalendarRange.month(selected),
        );
  }

  Future<void> _refresh() async {
    setState(_load);
    await events;
  }

  Future<void> _create(MobileCalendarDraft draft) async {
    try {
      await SiteEventService().create(
        widget.employerId,
        title: draft.title,
        type: draft.reminder ? 'reminder' : 'other',
        start: draft.start,
        end: draft.end,
        allDay: false,
        description: draft.notes,
        reminderOffsetsMinutes:
            draft.alertMinutes < 0 ? [] : [draft.alertMinutes],
      );
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save calendar entry. Try again.')));
      }
    }
  }

  Future<void> _edit(CalendarEvent event, MobileCalendarDraft draft) async {
    if (!event.id.startsWith('manual:')) return;
    try {
      final original =
          await SiteEventService().getOwn(widget.employerId, event.sourceId);
      if (original == null) return;
      await SiteEventService().update(widget.employerId, original,
          title: draft.title,
          type: draft.reminder ? 'reminder' : 'other',
          start: draft.start,
          end: draft.end,
          allDay: false,
          siteId: original.siteId,
          description: draft.notes,
          reminderOffsetsMinutes:
              draft.alertMinutes < 0 ? [] : [draft.alertMinutes]);
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update calendar entry.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final calendar = MobileCalendarView(
      key: ValueKey('${widget.employerId}-${selected.year}-${selected.month}'),
      selected: selected,
      events: events,
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
      onEditManual: _edit,
      canEditManual: (event) =>
          event.id.startsWith('manual:') &&
          event.siteId.isEmpty &&
          {'other', 'reminder'}.contains(event.eventType),
    );
    return widget.embedded
        ? calendar
        : Scaffold(
            backgroundColor: const Color(0xFF08293A),
            appBar: AppBar(title: const Text('Calendar')),
            body: SafeArea(child: calendar));
  }
}

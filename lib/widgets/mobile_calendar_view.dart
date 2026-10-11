import 'package:flutter/material.dart';

import '../services/operational_calendar.dart';

const mobileCalendarAlerts = <int, String>{
  -1: 'None',
  5: '5 minutes before',
  10: '10 minutes before',
  15: '15 minutes before',
  30: '30 minutes before',
  60: '1 hour before',
  120: '2 hours before',
  1440: '1 day before',
  2880: '2 days before',
  10080: '1 week before',
};

class MobileCalendarDraft {
  const MobileCalendarDraft({
    required this.title,
    required this.start,
    required this.end,
    required this.reminder,
    required this.alertMinutes,
    required this.notes,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final bool reminder;
  final int alertMinutes;
  final String notes;
}

Future<MobileCalendarDraft?> showMobileCalendarEditor(
    BuildContext context, DateTime day,
    {MobileCalendarDraft? initial}) async {
  final choice = initial?.reminder ??
      await showModalBottomSheet<bool>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Event'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Reminder'),
              onTap: () => Navigator.pop(context, true),
            ),
          ]),
        ),
      );
  if (choice == null || !context.mounted) return null;
  return showModalBottomSheet<MobileCalendarDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _CalendarEditor(day: day, reminder: choice, initial: initial),
  );
}

class _CalendarEditor extends StatefulWidget {
  const _CalendarEditor(
      {required this.day, required this.reminder, this.initial});
  final DateTime day;
  final bool reminder;
  final MobileCalendarDraft? initial;

  @override
  State<_CalendarEditor> createState() => _CalendarEditorState();
}

class _CalendarEditorState extends State<_CalendarEditor> {
  final title = TextEditingController();
  final notes = TextEditingController();
  late DateTime start;
  late DateTime end;
  int alert = -1;
  String? error;

  @override
  void initState() {
    super.initState();
    title.text = widget.initial?.title ?? '';
    notes.text = widget.initial?.notes ?? '';
    alert = widget.initial?.alertMinutes ?? -1;
    start = widget.initial?.start ??
        DateTime(widget.day.year, widget.day.month, widget.day.day, 9);
    end = widget.initial?.end ??
        DateTime(widget.day.year, widget.day.month, widget.day.day,
            widget.reminder ? 9 : 10);
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(bool forStart) async {
    final original = forStart ? start : end;
    final date = await showDatePicker(
      context: context,
      initialDate: original,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(original));
    if (time == null || !mounted) return;
    final value =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (forStart) {
        start = value;
      } else {
        end = value;
      }
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dates = MaterialLocalizations.of(context);
    String label(DateTime value) =>
        '${dates.formatMediumDate(value)}  ${dates.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.reminder ? 'New reminder' : 'New event',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              key: const Key('calendar-title'),
              controller: title,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            ListTile(
              title: const Text('Start'),
              subtitle: Text(label(start)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () => _pickDateTime(true),
            ),
            if (!widget.reminder)
              ListTile(
                title: const Text('End'),
                subtitle: Text(label(end)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () => _pickDateTime(false),
              ),
            DropdownButtonFormField<int>(
              initialValue: alert,
              decoration: const InputDecoration(labelText: 'Alert'),
              items: [
                if (!mobileCalendarAlerts.containsKey(alert))
                  DropdownMenuItem(
                      value: alert, child: Text('$alert minutes before')),
                for (final choice in mobileCalendarAlerts.entries)
                  DropdownMenuItem(
                      value: choice.key, child: Text(choice.value)),
              ],
              onChanged: (value) => setState(() => alert = value ?? -1),
            ),
            if (!widget.reminder)
              TextField(
                controller: notes,
                maxLines: 2,
                maxLength: 1000,
                decoration:
                    const InputDecoration(labelText: 'Notes (optional)'),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final last = widget.reminder ? start : end;
                  if (title.text.trim().isEmpty || last.isBefore(start)) {
                    setState(
                        () => error = 'Enter a title and check the dates.');
                    return;
                  }
                  Navigator.pop(
                      context,
                      MobileCalendarDraft(
                        title: title.text.trim(),
                        start: start,
                        end: last,
                        reminder: widget.reminder,
                        alertMinutes: alert,
                        notes: notes.text.trim(),
                      ));
                },
                child: const Text('Save'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class MobileCalendarView extends StatefulWidget {
  const MobileCalendarView({
    super.key,
    required this.selected,
    required this.events,
    required this.onSelect,
    required this.onMove,
    required this.onRefresh,
    required this.onCreate,
    this.leading,
    this.onExportAssignment,
    this.onEditManual,
    this.canEditManual,
  });

  final DateTime selected;
  final Future<List<CalendarEvent>> events;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onMove;
  final Future<void> Function() onRefresh;
  final Future<void> Function(MobileCalendarDraft) onCreate;
  final Widget? leading;
  final ValueChanged<CalendarEvent>? onExportAssignment;
  final Future<void> Function(CalendarEvent, MobileCalendarDraft)? onEditManual;
  final bool Function(CalendarEvent)? canEditManual;

  @override
  State<MobileCalendarView> createState() => _MobileCalendarViewState();
}

class _MobileCalendarViewState extends State<MobileCalendarView> {
  String query = '';
  bool searching = false;

  @override
  Widget build(BuildContext context) {
    final range = CalendarRange.month(widget.selected);
    final dayCount = range.end.difference(range.start).inDays;
    final theme = Theme.of(context);
    const light = Colors.white;
    return FutureBuilder<List<CalendarEvent>>(
      future: widget.events,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <CalendarEvent>[];
        if (snapshot.hasError) {
          return Center(
              child: TextButton(
                  onPressed: widget.onRefresh,
                  child: const Text('Could not load calendar. Retry')));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final searchingTitles = query.trim().isNotEmpty;
        final dayEvents = all
            .where((event) =>
                (searchingTitles ||
                    CalendarRange.day(widget.selected).contains(event.date)) &&
                event.title.toLowerCase().contains(query.trim().toLowerCase()))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
            children: [
              if (widget.leading != null) widget.leading!,
              Row(children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => widget.onMove(-1),
                  icon: const Icon(Icons.chevron_left, color: light),
                ),
                Expanded(
                    child: Text(
                        MaterialLocalizations.of(context)
                            .formatMonthYear(widget.selected),
                        style: theme.textTheme.titleLarge
                            ?.copyWith(color: light))),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () => widget.onMove(1),
                  icon: const Icon(Icons.chevron_right, color: light),
                ),
                IconButton(
                  tooltip: 'Search calendar',
                  onPressed: () => setState(() => searching = !searching),
                  icon: const Icon(Icons.search, color: light),
                ),
                IconButton(
                  key: const Key('calendar-create'),
                  tooltip: 'Create calendar entry',
                  onPressed: () async {
                    final draft = await showMobileCalendarEditor(
                        context, widget.selected);
                    if (draft != null && context.mounted) {
                      await widget.onCreate(draft);
                    }
                  },
                  icon: const Icon(Icons.add, color: light),
                ),
              ]),
              if (searching)
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: 'Search event titles',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (value) => setState(() => query = value),
                ),
              Row(children: [
                for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                  Expanded(
                      child: Center(
                          child: Text(label,
                              style: const TextStyle(
                                  color: light, fontWeight: FontWeight.w700)))),
              ]),
              const SizedBox(height: 6),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: dayCount,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7, mainAxisExtent: 74),
                itemBuilder: (context, index) {
                  final day = range.start.add(Duration(days: index));
                  final entries = all
                      .where((event) =>
                          CalendarRange.day(day).contains(event.date))
                      .toList();
                  final selected =
                      CalendarRange.day(day).contains(widget.selected);
                  final inMonth = day.month == widget.selected.month;
                  return InkWell(
                    key:
                        Key('calendar-day-${day.year}-${day.month}-${day.day}'),
                    onTap: () => widget.onSelect(day),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFEAF6FC)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: selected
                                ? light
                                : light.withValues(alpha: .22)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${day.day}',
                              style: TextStyle(
                                  color: selected
                                      ? Colors.black
                                      : (inMonth
                                          ? light
                                          : light.withValues(alpha: .5)),
                                  fontWeight: FontWeight.w700)),
                          for (final event in entries.take(2))
                            Text(event.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 9,
                                    color: selected ? Colors.black87 : light)),
                          if (entries.length > 2)
                            Text('+${entries.length - 2}',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: selected ? Colors.black87 : light)),
                          const Spacer(),
                          if (entries.isNotEmpty)
                            Align(
                                alignment: Alignment.bottomRight,
                                child: Icon(Icons.notifications_none,
                                    size: 12,
                                    color: selected ? Colors.black87 : light)),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                  searchingTitles
                      ? 'Search results'
                      : MaterialLocalizations.of(context)
                          .formatMediumDate(widget.selected),
                  style: theme.textTheme.titleMedium?.copyWith(color: light)),
              if (dayEvents.isEmpty)
                const ListTile(
                    title: Text('No events for this day',
                        style: TextStyle(color: light))),
              for (final event in dayEvents)
                ListTile(
                  title: Text(event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: light)),
                  subtitle: Text(
                      [
                        event.type == CalendarEventType.manual
                            ? event.eventType
                            : event.typeLabel,
                        event.siteName,
                        event.trade,
                        if (searchingTitles)
                          MaterialLocalizations.of(context)
                              .formatMediumDate(event.date),
                      ].where((part) => part.isNotEmpty).toSet().join(' · '),
                      style: TextStyle(color: light.withValues(alpha: .75))),
                  trailing: widget.onExportAssignment != null &&
                          {
                            CalendarEventType.assignmentStart,
                            CalendarEventType.assignmentOngoing,
                            CalendarEventType.assignmentFinish,
                          }.contains(event.type)
                      ? IconButton(
                          tooltip: 'Add to Calendar',
                          icon: const Icon(Icons.event_available_outlined,
                              color: light),
                          onPressed: () => widget.onExportAssignment!(event),
                        )
                      : null,
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(event.title),
                      content: Text([
                        event.description,
                        event.siteName,
                        event.trade
                      ].where((part) => part.isNotEmpty).join('\n')),
                      actions: [
                        if (widget.onEditManual != null &&
                            event.type == CalendarEventType.manual &&
                            (widget.canEditManual?.call(event) ?? true))
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              final draft = await showMobileCalendarEditor(
                                this.context,
                                event.date,
                                initial: MobileCalendarDraft(
                                  title: event.title,
                                  start: event.date,
                                  end: event.end ?? event.date,
                                  reminder: event.eventType == 'reminder',
                                  alertMinutes: event.alertMinutes,
                                  notes: event.description,
                                ),
                              );
                              if (draft != null && mounted) {
                                await widget.onEditManual!(event, draft);
                              }
                            },
                            child: const Text('Edit'),
                          ),
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'))
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

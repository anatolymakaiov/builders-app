import 'package:flutter/material.dart';

import '../services/operational_calendar.dart';
import '../services/worker_assignment_service.dart';

class WorkerCalendarScreen extends StatefulWidget {
  const WorkerCalendarScreen({super.key, required this.workerId});

  final String workerId;

  @override
  State<WorkerCalendarScreen> createState() => _WorkerCalendarScreenState();
}

class _WorkerCalendarScreenState extends State<WorkerCalendarScreen> {
  final service = OperationalCalendarService();
  late Future<List<CalendarEvent>> events;
  late Future<List<WorkerAssignment>> assignments;
  DateTime selected = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    assignments = service.loadCurrentNext(widget.workerId);
  }

  void _load() => events = service.load(
      uid: widget.workerId,
      employer: false,
      range: CalendarRange.month(selected));

  void _move(int delta) => setState(() {
        selected = DateTime(selected.year, selected.month + delta, 1);
        _load();
      });

  String _date(DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value);

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
            assignments = service.loadCurrentNext(widget.workerId);
          });
          await events;
        },
        child: ListView(padding: const EdgeInsets.all(16), children: [
          FutureBuilder<List<WorkerAssignment>>(
            future: assignments,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return TextButton.icon(
                  onPressed: () => setState(() =>
                      assignments = service.loadCurrentNext(widget.workerId)),
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

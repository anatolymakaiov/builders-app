import 'package:flutter/material.dart';

import '../services/operational_calendar.dart';

class EmployerCalendarScreen extends StatefulWidget {
  const EmployerCalendarScreen(
      {super.key, required this.employerId, this.initialDate, this.loadEvents});

  final String employerId;
  final DateTime? initialDate;
  final Future<List<CalendarEvent>> Function(CalendarRange)? loadEvents;

  @override
  State<EmployerCalendarScreen> createState() => _EmployerCalendarScreenState();
}

class _EmployerCalendarScreenState extends State<EmployerCalendarScreen> {
  DateTime selected = DateTime.now();
  late Future<List<CalendarEvent>> events;

  @override
  void initState() {
    super.initState();
    selected = widget.initialDate ?? DateTime.now();
    _load();
  }

  void _load() {
    events = widget.loadEvents?.call(CalendarRange.month(selected)) ??
        OperationalCalendarService().load(
            uid: widget.employerId,
            employer: true,
            range: CalendarRange.month(selected));
  }

  void _move(int months) => setState(() {
        selected = DateTime(selected.year, selected.month + months);
        _load();
      });

  Future<void> _refresh() async {
    setState(_load);
    await events;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Calendar')),
        body: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _move(-1)),
            Text(MaterialLocalizations.of(context).formatMonthYear(selected),
                style: Theme.of(context).textTheme.titleMedium),
            IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _move(1)),
          ]),
          Expanded(
              child: FutureBuilder<List<CalendarEvent>>(
            future: events,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: TextButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Could not load calendar. Retry'),
                  onPressed: () => setState(_load),
                ));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = snapshot.data!
                  .where((item) =>
                      item.date.year == selected.year &&
                      item.date.month == selected.month)
                  .toList()
                ..sort((a, b) => a.date.compareTo(b.date));
              return RefreshIndicator(
                onRefresh: _refresh,
                child: entries.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          ListTile(title: Text('No events this month.'))
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final event = entries[index];
                          return ListTile(
                            leading:
                                CircleAvatar(child: Text('${event.date.day}')),
                            title: Text('${event.typeLabel} · ${event.title}'),
                            subtitle: Text([
                              MaterialLocalizations.of(context)
                                  .formatMediumDate(event.date),
                              event.siteName,
                              event.trade,
                            ]
                                .where((text) => text.isNotEmpty)
                                .toSet()
                                .join(' · ')),
                          );
                        },
                      ),
              );
            },
          )),
        ]),
      );
}

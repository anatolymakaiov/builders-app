import 'package:flutter/material.dart';

import '../../../services/operational_calendar.dart';
import '../../../services/worker_assignment_service.dart';
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
      this.onOpenJob,
      this.onOpenSite,
      this.refreshToken = 0,
      this.loadEvents,
      this.loadCurrentNext,
      this.employerSites});

  final String uid;
  final bool employer;
  final String? initialSiteId;
  final ValueChanged<String>? onOpenJob;
  final ValueChanged<String>? onOpenSite;
  final int refreshToken;
  final Future<List<CalendarEvent>> Function(CalendarRange)? loadEvents;
  final Future<List<WorkerAssignment>> Function()? loadCurrentNext;
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

  @override
  void initState() {
    super.initState();
    siteId = widget.initialSiteId;
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
      selectedDay = DateTime.now();
      sites = widget.employerSites ??
          (widget.employer
              ? WebSitesService().watchEmployerSites(widget.uid)
              : const Stream<List<WebSite>>.empty());
      _load();
      if (!widget.employer) _loadCurrentNext();
    } else if (oldWidget.initialSiteId != widget.initialSiteId) {
      siteId = widget.initialSiteId;
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

  void _load() => events = widget.loadEvents?.call(range) ??
      service.load(uid: widget.uid, employer: widget.employer, range: range);

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
            day = day.add(const Duration(days: 1)))
          Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_date(day),
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
              },
              color: WebTheme.accent),
          title: Text('${event.typeLabel}: ${event.title}'),
          subtitle: Text([event.siteName, event.trade]
              .where((part) => part.isNotEmpty)
              .toSet()
              .join(' · ')),
          trailing: event.vacancyId.isNotEmpty || event.siteId.isNotEmpty
              ? const Icon(Icons.chevron_right)
              : null,
          onTap: () {
            if (widget.employer &&
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

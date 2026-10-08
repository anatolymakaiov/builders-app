import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/operational_calendar.dart';
import 'package:test_app/services/worker_assignment_service.dart';

Timestamp day(int year, int month, int date) =>
    Timestamp.fromDate(DateTime(year, month, date, 12));

void main() {
  final month = CalendarRange.month(DateTime(2026, 10, 15));

  test('month week day ranges have inclusive dates and exclusive end', () {
    expect(month.start.weekday, DateTime.monday);
    expect(month.end.weekday, DateTime.monday);
    expect(month.contains(DateTime(2026, 10, 1)), isTrue);
    expect(month.contains(month.end), isFalse);
    final week = CalendarRange.week(DateTime(2026, 10, 15));
    expect(week.start.weekday, DateTime.monday);
    expect(week.end.difference(week.start).inDays, 7);
    final dayRange = CalendarRange.day(DateTime(2026, 10, 15));
    expect(dayRange.contains(DateTime(2026, 10, 15, 23, 59)), isTrue);
    expect(dayRange.contains(DateTime(2026, 10, 16)), isFalse);
  });

  test('week boundaries remain local midnight across UK DST change', () {
    final week = CalendarRange.week(DateTime(2026, 10, 25));
    expect(week.start.weekday, DateTime.monday);
    expect(week.start.hour, 0);
    expect(week.end.weekday, DateTime.monday);
    expect(week.end.hour, 0);
    expect(week.contains(DateTime(2026, 10, 25, 23)), isTrue);
  });

  test('vacancy start derives only from a real date and meaningful status', () {
    final data = {
      'startDate': day(2026, 10, 15),
      'status': 'active',
      'siteId': 'site-a',
      'title': 'Dryliner'
    };
    final events = vacancyCalendarEvents('job-a', data, month);
    expect(events.single.type, CalendarEventType.vacancyStart);
    expect(events.single.vacancyId, 'job-a');
    expect(
        vacancyCalendarEvents('job-a', {...data}..remove('startDate'), month),
        isEmpty);
    expect(
        vacancyCalendarEvents('job-a', {...data, 'status': 'deleted'}, month),
        isEmpty);
    expect(vacancyCalendarEvents('job-a', {...data, 'deleted': true}, month),
        isEmpty);
    expect(
        vacancyCalendarEvents(
            'job-a', {...data, 'moderationStatus': 'pending_review'}, month),
        isEmpty);
  });

  test('assignment start and expected finish derive without duplicates', () {
    final data = {
      'startDate': day(2026, 10, 15),
      'expectedEndDate': day(2026, 10, 20),
      'status': 'scheduled',
      'workerDisplayName': 'Worker A',
      'siteId': 'site-a',
      'vacancyId': 'job-a',
      'tradeName': 'Electrician'
    };
    final events = assignmentCalendarEvents('a', data, month);
    expect(events.map((event) => event.type), [
      CalendarEventType.assignmentStart,
      CalendarEventType.assignmentFinish,
    ]);
    expect(events.first.title, contains('Worker A'));
    expect(
        assignmentCalendarEvents(
            'a', {...data, 'expectedEndDate': day(2026, 10, 15)}, month),
        hasLength(1));
  });

  test('actual end overrides expected, cancelled never appears active', () {
    final data = {
      'startDate': day(2026, 10, 15),
      'expectedEndDate': day(2026, 10, 20),
      'actualEndDate': day(2026, 10, 18),
      'status': 'completed'
    };
    final events = assignmentCalendarEvents('a', data, month);
    expect(events.last.date.day, 18);
    expect(
        assignmentCalendarEvents('a', {...data, 'status': 'cancelled'}, month),
        isEmpty);
    expect(
        assignmentSpansDate(
            {...data, 'status': 'cancelled'}, DateTime(2026, 10, 16)),
        isFalse);
  });

  test('span boundary and legacy site-less assignment', () {
    final data = {
      'startDate': day(2026, 10, 1),
      'expectedEndDate': day(2026, 10, 20),
      'status': 'active'
    };
    expect(assignmentSpansDate(data, DateTime(2026, 10, 1)), isTrue);
    expect(assignmentSpansDate(data, DateTime(2026, 10, 20)), isTrue);
    expect(assignmentSpansDate(data, DateTime(2026, 10, 21)), isFalse);
    expect(assignmentCalendarEvents('legacy', data, month).first.siteId, '');
    final period = assignmentPeriodEvents(
        'legacy', data, CalendarRange.week(DateTime(2026, 10, 14)));
    expect(period, isNotEmpty);
    expect(
        period.every(
            (event) => event.type == CalendarEventType.assignmentOngoing),
        isTrue);
    expect(period.map((event) => event.id).toSet(), hasLength(period.length));
    expect(
        assignmentPeriodEvents(
            'legacy', {...data, 'status': 'cancelled'}, month),
        isEmpty);
    expect(
        assignmentPeriodEvents(
            'legacy', {...data, 'status': 'scheduled'}, month),
        isEmpty);
  });

  test('site filtering uses siteId, including legacy empty siteId', () {
    final linked = assignmentCalendarEvents(
        'linked',
        {
          'startDate': day(2026, 10, 15),
          'siteId': 'a',
        },
        month);
    final legacy = assignmentCalendarEvents(
        'legacy',
        {
          'startDate': day(2026, 10, 15),
          'siteName': 'Site A',
        },
        month);
    final all = [...linked, ...legacy];
    expect(filterCalendarEventsBySite(all, null), hasLength(2));
    expect(filterCalendarEventsBySite(all, 'a').single.sourceId, 'linked');
    expect(filterCalendarEventsBySite(all, '').single.sourceId, 'legacy');
  });

  test('current and next assignment selection excludes ended work', () {
    final now = DateTime(2026, 10, 15, 12);
    WorkerAssignment item(String id, String status, int start, int end) =>
        WorkerAssignment(id, {
          'status': status,
          'startDate': day(2026, 10, start),
          'expectedEndDate': day(2026, 10, end)
        });
    final old = item('old', 'active', 1, 10);
    final current = item('current', 'active', 12, 20);
    final next = item('next', 'scheduled', 25, 30);
    expect(
        currentOrNextAssignment([next, old, current], now: now)!.assignment.id,
        'current');
    expect(
        currentOrNextAssignment([next, old], now: now)!.assignment.id, 'next');
    expect(currentOrNextAssignment([old], now: now), isNull);
  });

  test('worker unavailable period renders only in its date range', () {
    final events = unavailableCalendarEvents(
        'private',
        {
          'startDate': day(2026, 10, 15),
          'endDate': day(2026, 10, 17),
          'type': 'holiday',
          'note': 'Private note',
        },
        CalendarRange.week(DateTime(2026, 10, 16)));
    expect(events, hasLength(3));
    expect(events.every((event) => event.type == CalendarEventType.unavailable),
        isTrue);
    expect(events.first.title, 'Unavailable');
    expect(events.first.siteName, 'Private note');
  });

  test('site milestones are derived, including archived history', () {
    final archived = {
      'name': 'Tower',
      'status': 'archived',
      'startDate': day(2026, 10, 10),
      'expectedEndDate': day(2026, 10, 28),
    };
    final events = siteMilestoneEvents('site-a', archived, month);
    expect(events.map((event) => event.type),
        [CalendarEventType.siteStart, CalendarEventType.siteFinish]);
    expect(events.every((event) => event.siteId == 'site-a'), isTrue);
    expect(siteMilestoneEvents('site-a', {'name': 'Undated'}, month), isEmpty);
  });

  test('manual employer events remain scoped by site and calendar day', () {
    final linked = manualSiteCalendarEvents(
        'event-a',
        {
          'siteId': 'site-a',
          'title': 'Inspection',
          'eventType': 'inspection',
          'startDateTime': day(2026, 10, 15),
          'description': 'Scaffold',
          'allDay': false,
        },
        month);
    final company = manualSiteCalendarEvents(
        'event-b',
        {
          'siteId': '',
          'title': 'Meeting',
          'startDateTime': day(2026, 10, 16),
        },
        month);
    expect(linked.single.sourceId, 'event-a');
    expect(linked.single.description, 'Scaffold');
    expect(filterCalendarEventsBySite([...linked, ...company], 'site-a'),
        hasLength(1));
    expect(
        filterCalendarEventsBySite([...linked, ...company], ''), hasLength(1));
    expect(
        manualSiteCalendarEvents(
            'event-a',
            {
              'startDateTime': day(2026, 12, 15),
            },
            month),
        isEmpty);
  });
}

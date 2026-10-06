import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/calendar_export.dart';
import 'package:test_app/services/operational_calendar.dart';

void main() {
  final range = CalendarRange(DateTime(2026, 10, 1), DateTime(2026, 11, 1));
  final start = Timestamp.fromDate(DateTime.utc(2026, 10, 6));
  final end = Timestamp.fromDate(DateTime.utc(2026, 10, 20));

  test('valid calendar, stable UID, inclusive source end and empty export', () {
    final event = CalendarExportEvent(
        sourceType: 'assignment',
        sourceId: 'a1',
        title: 'Dryliner',
        start: DateTime(2026, 10, 6),
        end: DateTime(2026, 10, 20));
    const provider = IcsCalendarProvider();
    final content =
        provider.exportEvents([event], now: DateTime.utc(2026, 10, 1));
    expect(content, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
    expect(content, contains('UID:assignment-a1@stroyka.uk\r\n'));
    expect(content, contains('DTSTART;VALUE=DATE:20261006\r\n'));
    expect(content, contains('DTEND;VALUE=DATE:20261021\r\n'));
    expect(content, contains('DTSTAMP:20261001T000000Z\r\n'));
    expect(content, endsWith('END:VCALENDAR\r\n'));
    expect(provider.exportEvents([], now: DateTime.utc(2026)),
        isNot(contains('BEGIN:VEVENT')));
    expect(provider.exportEvents([event], now: DateTime.utc(2026, 10, 1)),
        content);
  });

  test('timed events use UTC and omit unknown end', () {
    final event = CalendarExportEvent(
        sourceType: 'assignment',
        sourceId: 'timed',
        title: 'Meeting',
        start: DateTime.utc(2026, 10, 6, 9, 30),
        allDay: false);
    final content = const IcsCalendarProvider().exportEvents([event]);
    expect(content, contains('DTSTART:20261006T093000Z'));
    expect(content, isNot(contains('DTEND:')));
  });

  test('employer export includes manual event and derived site milestones', () {
    final site = siteMilestoneExportEvents('site-a', {
      'employerContextId': 'employer-a', 'name': 'Tower',
      'startDate': start, 'expectedEndDate': end,
    }, employerId: 'employer-a', range: range);
    final manual = manualSiteExportEvent('meeting-a', {
      'employerContextId': 'employer-a', 'siteId': 'site-a',
      'title': 'Safety briefing', 'eventType': 'safety_briefing',
      'startDateTime': Timestamp.fromDate(DateTime.utc(2026, 10, 8, 9)),
      'allDay': false, 'description': 'Bring PPE',
    }, employerId: 'employer-a', range: range);
    expect(site, hasLength(2));
    expect(manual, isNotNull);
    final export = const IcsCalendarProvider().exportEvents([...site, manual!]);
    expect(export, contains('UID:site-site-a-start@stroyka.uk'));
    expect(export, contains('UID:site-event-meeting-a@stroyka.uk'));
    expect(export, contains('SUMMARY:Safety briefing'));
    expect(filterCalendarExportBySite([...site, manual], 'other'), isEmpty);
    expect(manualSiteExportEvent('meeting-a', {
      'employerContextId': 'employer-a', 'startDateTime': start,
    }, employerId: 'worker-a', range: range), isNull);
  });

  test('text escaping and UTF-8 octet folding preserve long content', () {
    final description = 'Café, Tower; \\ West\n${'é' * 70}';
    final content = const IcsCalendarProvider().exportEvents([
      CalendarExportEvent(
          sourceType: 'assignment',
          sourceId: 'a',
          title: 'Café, site;',
          start: DateTime(2026, 10, 6),
          description: description)
    ]);
    expect(content, contains('SUMMARY:Café\\, site\\;'));
    expect(content.replaceAll('\r\n ', ''),
        contains(r'DESCRIPTION:Café\, Tower\; \\ West\n'));
    for (final line in content.split('\r\n')) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75));
    }
    expect(content, contains('\r\n '));
  });

  test('worker only maps own active assignment, not application or cancelled',
      () {
    final data = <String, dynamic>{
      'workerId': 'worker-a',
      'employerContextId': 'employer-a',
      'status': 'scheduled',
      'startDate': start,
      'expectedEndDate': end,
      'tradeName': 'Dryliner',
      'siteName': 'Tower',
      'employerName': 'Builder',
      'workerDisplayName': 'Anthony M.',
      'siteId': 'site-a',
      'phone': 'PRIVATE_PHONE',
      'email': 'PRIVATE_EMAIL',
      'homeAddress': 'PRIVATE_HOME',
      'rate': 'PRIVATE_BILLING',
    };
    final own = assignmentExportEvent('a1', data,
        uid: 'worker-a', employer: false, range: range);
    expect(own, isNotNull);
    expect(own!.siteId, 'site-a');
    final content = const IcsCalendarProvider().exportEvents([own]);
    expect(content, contains('Employer: Builder'));
    for (final secret in [
      'PRIVATE_PHONE',
      'PRIVATE_EMAIL',
      'PRIVATE_HOME',
      'PRIVATE_BILLING'
    ]) {
      expect(content, isNot(contains(secret)));
    }
    expect(
        assignmentExportEvent('a1', data,
            uid: 'worker-b', employer: false, range: range),
        isNull);
    expect(
        assignmentExportEvent('a1', {...data, 'status': 'cancelled'},
            uid: 'worker-a', employer: false, range: range),
        isNull);
    expect(
        vacancyExportEvent(
            'v1',
            {
              'ownerId': 'employer-a',
              'startDate': start,
              'status': 'active',
              'moderationStatus': 'approved'
            },
            employerId: 'worker-a',
            range: range),
        isNull);
  });

  test('employer only maps own sites and safe worker identity', () {
    final data = <String, dynamic>{
      'workerId': 'worker-a',
      'employerContextId': 'employer-a',
      'status': 'active',
      'startDate': start,
      'workerDisplayName': 'Anthony M.',
      'siteName': 'Tower',
      'siteId': 'site-a',
      'workerEmail': 'PRIVATE_EMAIL',
    };
    final event = assignmentExportEvent('a1', data,
        uid: 'employer-a', employer: true, range: range);
    expect(event, isNotNull);
    expect(event!.description, contains('Worker: Anthony M.'));
    expect(event.description, isNot(contains('PRIVATE_EMAIL')));
    expect(
        assignmentExportEvent('a1', data,
            uid: 'employer-b', employer: true, range: range),
        isNull);
    expect(
        vacancyExportEvent(
                'v1',
                {
                  'ownerId': 'employer-a',
                  'startDate': start,
                  'status': 'active',
                  'moderationStatus': 'approved',
                  'siteId': 'site-a',
                  'trade': 'Dryliner'
                },
                employerId: 'employer-a',
                range: range)
            ?.siteId,
        'site-a');
  });

  test('worker unavailability never exports private note or foreign period',
      () {
    final data = <String, dynamic>{
      'workerId': 'worker-a',
      'startDate': start,
      'endDate': end,
      'type': 'holiday',
      'note': 'PRIVATE_NOTE'
    };
    final event = unavailabilityExportEvent('u1', data,
        workerId: 'worker-a', range: range);
    expect(event?.title, 'Holiday');
    expect(const IcsCalendarProvider().exportEvents([event!]),
        isNot(contains('PRIVATE_NOTE')));
    expect(
        unavailabilityExportEvent('u1', data,
            workerId: 'worker-b', range: range),
        isNull);
  });

  test('provider foundation does not claim Google or Outlook sync', () {
    final capabilities = const IcsCalendarProvider().providerCapabilities;
    expect(capabilities.where((c) => c.available).single.provider,
        ExternalCalendarProvider.ics);
    expect(
        capabilities.where((c) => !c.available).map((c) => c.provider),
        containsAll([
          ExternalCalendarProvider.google,
          ExternalCalendarProvider.outlook
        ]));
  });

  test('site export includes only selected site, all-sites retains all', () {
    final events = [
      CalendarExportEvent(
          sourceType: 'assignment',
          sourceId: 'a',
          title: 'A',
          start: DateTime(2026, 10, 6),
          siteId: 'site-a'),
      CalendarExportEvent(
          sourceType: 'vacancy',
          sourceId: 'b',
          title: 'B',
          start: DateTime(2026, 10, 6),
          siteId: 'site-b'),
      CalendarExportEvent(
          sourceType: 'unavailability',
          sourceId: 'c',
          title: 'Unavailable',
          start: DateTime(2026, 10, 6)),
    ];
    expect(filterCalendarExportBySite(events, 'site-a').map((e) => e.sourceId),
        ['a']);
    expect(filterCalendarExportBySite(events, null), hasLength(3));
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/operational_calendar.dart';
import 'package:test_app/services/calendar_export.dart';
import 'package:test_app/services/worker_assignment_service.dart';
import 'package:test_app/web_app/pages/calendar/web_calendar_page.dart';
import 'package:test_app/web_app/services/web_sites_service.dart';
import 'package:test_app/web_app/shell/web_top_navigation.dart';

CalendarEvent event(String id, String siteId, DateTime date) => CalendarEvent(
      id: id,
      type: CalendarEventType.vacancyStart,
      date: date,
      title: 'Vacancy starts — $id',
      sourceId: id,
      vacancyId: id,
      siteId: siteId,
      siteName: siteId,
      trade: id,
      status: 'active',
    );

void main() {
  test('desktop navigation exposes Calendar', () {
    expect(WebSection.calendar.label, 'Calendar');
  });

  testWidgets('employer switches views, filters by site and opens vacancy',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final today = DateTime.now();
    final opened = <String>[];
    final ranges = <CalendarRange>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WebCalendarPage(
      uid: 'employer-a',
      employer: true,
      employerSites: Stream.value([
        const WebSite(id: 'site-a', data: {'name': 'Site A'}),
        const WebSite(id: 'site-b', data: {'name': 'Site B'}),
      ]),
      loadEvents: (range) async {
        ranges.add(range);
        return [
          event('Dryliner', 'site-a', today),
          event('Electrician', 'site-b', today)
        ];
      },
      onOpenJob: opened.add,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Vacancy: Vacancy starts — Dryliner'), findsOneWidget);
    await tester.tap(find.text('All Sites'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Site A').last);
    await tester.pumpAndSettle();
    expect(find.text('Vacancy: Vacancy starts — Dryliner'), findsOneWidget);
    expect(find.text('Vacancy: Vacancy starts — Electrician'), findsNothing);
    await tester.tap(find.text('Vacancy: Vacancy starts — Dryliner'));
    expect(opened, ['Dryliner']);
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(ranges.last.end.difference(ranges.last.start).inDays, 7);
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(ranges.last.end.difference(ranges.last.start).inDays, 1);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(ranges.last.contains(DateTime.now()), isTrue);
  });

  testWidgets('worker sees next assignment and calendar empty state',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final next = DateTime.now().add(const Duration(days: 5));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WebCalendarPage(
      uid: 'worker-a',
      employer: false,
      loadEvents: (_) async => [],
      loadCurrentNext: () async => [
        WorkerAssignment('a', {
          'status': 'scheduled',
          'siteName': 'Tower Site',
          'tradeName': 'Dryliner',
          'startDate': Timestamp.fromDate(next),
        })
      ],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Next assignment'), findsOneWidget);
    expect(find.textContaining('Tower Site'), findsOneWidget);
    expect(find.text('No scheduled work in this period'), findsOneWidget);
    expect(find.text('Week'), findsNothing);
  });

  testWidgets('employer export follows selected site and all-sites override',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final sites = <String?>[];
    final downloads = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WebCalendarPage(
      uid: 'employer-a',
      employer: true,
      employerSites: Stream.value([
        const WebSite(id: 'site-a', data: {'name': 'Site A'})
      ]),
      loadEvents: (_) async => [],
      loadExport: (range, siteId) async {
        sites.add(siteId);
        return [
          CalendarExportEvent(
              sourceType: 'assignment',
              sourceId: 'a1',
              title: 'Dryliner',
              start: range.start,
              siteId: siteId ?? '')
        ];
      },
      downloadIcs: (contents, filename) => downloads.add(contents),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Sites'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Site A').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export visible period'));
    await tester.pumpAndSettle();
    expect(sites.last, 'site-a');
    expect(downloads.last, contains('UID:assignment-a1@stroyka.uk'));
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export all sites'));
    await tester.pumpAndSettle();
    expect(sites.last, isNull);
  });

  testWidgets('worker can export visible period and add next assignment',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final downloaded = <String>[];
    final start = DateTime.now().add(const Duration(days: 3));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WebCalendarPage(
      uid: 'worker-a',
      employer: false,
      loadEvents: (_) async => [
        CalendarEvent(
          id: 'assignment:a2:start',
          type: CalendarEventType.assignmentStart,
          date: DateTime.now(),
          title: 'Dryliner',
          sourceId: 'a2',
          vacancyId: '',
          siteId: '',
          siteName: 'Tower',
          trade: 'Dryliner',
          status: 'scheduled',
        )
      ],
      loadCurrentNext: () async => [
        WorkerAssignment('a1', {
          'workerId': 'worker-a',
          'startDate': Timestamp.fromDate(start),
          'status': 'scheduled',
          'tradeName': 'Dryliner',
          'siteName': 'Tower',
        })
      ],
      loadExport: (_, __) async => [],
      loadSingleAssignment: (id, range) async => CalendarExportEvent(
          sourceType: 'assignment',
          sourceId: id,
          title: 'Selected',
          start: range.start),
      downloadIcs: (contents, _) => downloaded.add(contents),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Export visible period'), findsOneWidget);
    await tester.tap(find.byTooltip('Add to Calendar').first);
    await tester.pumpAndSettle();
    expect(downloaded.last, contains('UID:assignment-a1@stroyka.uk'));
    await tester.tap(find.byTooltip('Add to Calendar').last);
    await tester.pumpAndSettle();
    expect(downloaded.last, contains('UID:assignment-a2@stroyka.uk'));
    await tester.tap(find.text('Export visible period'));
    await tester.pumpAndSettle();
    expect(downloaded.last, contains('BEGIN:VCALENDAR'));
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/operational_calendar.dart';
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
}

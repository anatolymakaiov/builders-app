import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/operational_calendar.dart';
import 'package:test_app/widgets/mobile_calendar_view.dart';

void main() {
  test('agenda time labels use local 24-hour times and all-day fallback', () {
    CalendarEvent event(DateTime start, {DateTime? end, bool allDay = false}) =>
        CalendarEvent(
          id: 'event',
          type: CalendarEventType.manual,
          date: start,
          end: end,
          allDay: allDay,
          title: 'Site inspection',
          sourceId: 'event',
          vacancyId: '',
          siteId: '',
          siteName: '',
          trade: '',
          status: '',
        );
    final start = DateTime(2026, 10, 14, 9);
    expect(
        mobileCalendarEventTimeLabel(
            event(start, end: DateTime(2026, 10, 14, 10, 30))),
        '09:00–10:30');
    expect(mobileCalendarEventTimeLabel(event(start)), '09:00');
    expect(mobileCalendarEventTimeLabel(event(start, allDay: true)), 'All day');
  });

  testWidgets('selected-day agenda shows event time next to its title',
      (tester) async {
    final day = DateTime(2026, 10, 14, 9);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MobileCalendarView(
          selected: day,
          events: Future.value([
            CalendarEvent(
              id: 'personal:event',
              type: CalendarEventType.manual,
              date: day,
              end: day.add(const Duration(minutes: 90)),
              allDay: false,
              title: 'Site inspection',
              sourceId: 'event',
              vacancyId: '',
              siteId: '',
              siteName: '',
              trade: '',
              status: '',
              eventType: 'event',
            ),
          ]),
          onSelect: (_) {},
          onMove: (_) {},
          onRefresh: () async {},
          onCreate: (_) async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Site inspection'), findsNWidgets(2));
    expect(find.textContaining('09:00–10:30'), findsOneWidget);
  });

  testWidgets('Monday-first calendar shows selected day and event indicator',
      (tester) async {
    final day = DateTime(2026, 10, 11);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: MobileCalendarView(
        selected: day,
        events: Future.value([
          CalendarEvent(
            id: 'personal:event',
            type: CalendarEventType.manual,
            date: day,
            title: 'My appointment',
            sourceId: 'event',
            vacancyId: '',
            siteId: '',
            siteName: '',
            trade: '',
            status: '',
            eventType: 'event',
          )
        ]),
        onSelect: (_) {},
        onMove: (_) {},
        onRefresh: () async {},
        onCreate: (_) async {},
      ),
    )));
    await tester.pumpAndSettle();
    for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('My appointment'), findsNWidgets(2));
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    expect(find.byKey(const Key('calendar-day-2026-10-11')), findsOneWidget);
  });

  testWidgets('plus opens Event/Reminder and defaults dates to selected day',
      (tester) async {
    final day = DateTime(2026, 10, 11);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: MobileCalendarView(
        selected: day,
        events: Future.value(const []),
        onSelect: (_) {},
        onMove: (_) {},
        onRefresh: () async {},
        onCreate: (_) async {},
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar-create')));
    await tester.pumpAndSettle();
    expect(find.text('Event'), findsOneWidget);
    expect(find.text('Reminder'), findsOneWidget);
    expect(find.text('Mark unavailable period'), findsNothing);
    await tester.tap(find.text('Event'));
    await tester.pumpAndSettle();
    final formatted =
        MaterialLocalizations.of(tester.element(find.text('Start')))
            .formatMediumDate(day);
    expect(find.textContaining(formatted), findsNWidgets(3));
    await tester.tap(find.text('None').last);
    await tester.pumpAndSettle();
    for (final option in mobileCalendarAlerts.values) {
      expect(find.text(option).last, findsOneWidget);
    }
  });

  testWidgets('owned manual event opens edit form with existing values',
      (tester) async {
    final day = DateTime(2026, 10, 11, 9);
    final event = CalendarEvent(
      id: 'personal:event',
      type: CalendarEventType.manual,
      date: day,
      title: 'My appointment',
      sourceId: 'event',
      vacancyId: '',
      siteId: '',
      siteName: '',
      trade: '',
      status: '',
      eventType: 'event',
      end: day.add(const Duration(hours: 1)),
      alertMinutes: 15,
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: MobileCalendarView(
        selected: day,
        events: Future.value([event]),
        onSelect: (_) {},
        onMove: (_) {},
        onRefresh: () async {},
        onCreate: (_) async {},
        onEditManual: (_, __) async {},
        canEditManual: (_) => true,
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('New event'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'My appointment'), findsOneWidget);
    expect(find.text('15 minutes before'), findsOneWidget);
  });
}

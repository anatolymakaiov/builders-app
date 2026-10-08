import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/screens/employer_calendar_screen.dart';
import 'package:test_app/services/operational_calendar.dart';

void main() {
  testWidgets('notification opens the employer agenda in its event month',
      (tester) async {
    final eventDate = DateTime(2026, 11, 2, 9);
    CalendarRange? loaded;
    await tester.pumpWidget(MaterialApp(
      home: EmployerCalendarScreen(
        employerId: 'employer-a',
        initialDate: eventDate,
        loadEvents: (range) async {
          loaded = range;
          return [];
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(loaded!.contains(eventDate), isTrue);
  });

  testWidgets('employer agenda shows assignment start and can refresh',
      (tester) async {
    var loads = 0;
    final today = DateTime.now();
    final event = CalendarEvent(
      id: 'assignment-a:start',
      type: CalendarEventType.assignmentStart,
      date: today,
      title: 'John M. starts — Dryliner',
      sourceId: 'assignment-a',
      vacancyId: 'job-a',
      siteId: 'site-a',
      siteName: 'Manchester Tower',
      trade: 'Dryliner',
      status: 'scheduled',
    );
    await tester.pumpWidget(MaterialApp(
        home: EmployerCalendarScreen(
      employerId: 'employer-a',
      loadEvents: (_) async {
        loads++;
        return [event];
      },
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('John M. starts'), findsOneWidget);
    expect(find.textContaining('Manchester Tower'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 320));
    await tester.pumpAndSettle();
    expect(loads, 2);
  });
}

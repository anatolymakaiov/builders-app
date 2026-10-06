import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/screens/worker_calendar_screen.dart';
import 'package:test_app/services/calendar_export.dart';
import 'package:test_app/services/operational_calendar.dart';
import 'package:test_app/services/worker_assignment_service.dart';

void main() {
  testWidgets('worker native calendar action uses own assignment',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    CalendarExportEvent? added;
    await tester.pumpWidget(MaterialApp(
        home: WorkerCalendarScreen(
      workerId: 'worker-a',
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
          'status': 'scheduled',
          'startDate':
              Timestamp.fromDate(DateTime.now().add(const Duration(days: 2))),
          'tradeName': 'Dryliner',
          'siteName': 'Tower',
        })
      ],
      addToCalendar: (event) async {
        added = event;
        return true;
      },
      loadSingleAssignment: (id, range) async => CalendarExportEvent(
          sourceType: 'assignment',
          sourceId: id,
          title: 'Selected',
          start: range.start),
    )));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add to Calendar'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Add to Calendar').first);
    await tester.pumpAndSettle();
    expect(added?.uid, 'assignment-a1@stroyka.uk');
    expect(added?.allDay, true);
    await tester.tap(find.byTooltip('Add to Calendar').last);
    await tester.pumpAndSettle();
    expect(added?.uid, 'assignment-a2@stroyka.uk');
  });
}

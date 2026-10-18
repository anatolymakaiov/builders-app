import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/screens/job_list_screen.dart';
import 'package:test_app/widgets/smart_job_search.dart';

void main() {
  for (final width in [360.0, 390.0]) {
    testWidgets('Jobs shell actions fit without overlap at ${width.toInt()}px',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      var opportunitiesOpened = false;
      await tester.pumpWidget(MaterialApp(
        home: JobListScreen(
          jobsStream: Stream.value(const <Job>[]),
          savedJobsStream: Stream.value(<String>{}),
          appliedJobsStream: Stream.value(<String>{}),
          userIdProvider: () => 'worker-a',
          lookupLocation: false,
          onOpenOpportunities: () => opportunitiesOpened = true,
          notificationAction: IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final opportunity = find.byTooltip('Opportunities');
      final notification = find.byTooltip('Notifications');
      expect(opportunity, findsOneWidget);
      expect(notification, findsOneWidget);
      expect(tester.takeException(), isNull);
      final titleRect = tester.getRect(find.text('Jobs'));
      final opportunityRect = tester.getRect(opportunity);
      final notificationRect = tester.getRect(notification);
      expect(opportunityRect.right, lessThan(titleRect.left));
      expect(titleRect.right, lessThan(notificationRect.left));
      await tester.tap(opportunity);
      expect(opportunitiesOpened, isTrue);
    });
  }

  testWidgets('Jobs search is compact and Ask STROYKA is in the app bar',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(MaterialApp(
        home: JobListScreen(
      jobsStream: Stream.value(const <Job>[]),
      savedJobsStream: Stream.value(<String>{}),
      appliedJobsStream: Stream.value(<String>{}),
      userIdProvider: () => 'worker-a',
      lookupLocation: false,
    )));
    await tester.pumpAndSettle();
    final search = find.byType(SmartJobSearchField);
    expect(search, findsOneWidget);
    expect(tester.getSize(search).height, inInclusiveRange(48, 64));
    final ask = find.byKey(const Key('ask-stroyka-mobile'));
    expect(ask, findsOneWidget);
    expect(
        find.ancestor(of: ask, matching: find.byType(AppBar)), findsOneWidget);
    expect(tester.getCenter(find.text('Jobs')).dx, closeTo(195, 0.5));
    expect(tester.getCenter(ask).dx, lessThan(195));
  });
  testWidgets('refresh keeps Jobs mounted after success, failure and retry',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final jobs = StreamController<List<Job>>.broadcast();
    addTearDown(jobs.close);
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: JobListScreen(
        jobsStream: jobs.stream,
        savedJobsStream: Stream.value(<String>{}),
        appliedJobsStream: Stream.value(<String>{}),
        userIdProvider: () => 'worker-a',
        lookupLocation: false,
        refreshAction: () async {
          attempts++;
          if (attempts == 2) throw StateError('offline');
          jobs.add(const <Job>[]);
        },
      ),
    ));
    jobs.add(const <Job>[]);
    await tester.pumpAndSettle();
    expect(find.text('No jobs found.'), findsOneWidget);

    Future<void> pull() async {
      await tester.drag(find.byType(ListView).first, const Offset(0, 350));
      await tester.pumpAndSettle();
    }

    await pull();
    expect(attempts, 1);
    expect(find.text('No jobs found.'), findsOneWidget);
    await pull();
    expect(attempts, 2);
    expect(find.text('No jobs found.'), findsOneWidget);
    expect(find.textContaining('Could not refresh jobs'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 3);
    expect(find.text('No jobs found.'), findsOneWidget);
  });

  testWidgets('user switch keeps Jobs results usable', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    var currentUser = 'worker-a';
    final page = JobListScreen(
      jobsStream: Stream.value(const <Job>[]),
      savedJobsStream: Stream.value(<String>{}),
      appliedJobsStream: Stream.value(<String>{}),
      userIdProvider: () => currentUser,
      lookupLocation: false,
      refreshAction: () async {},
    );
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
    expect(find.text('No jobs found.'), findsOneWidget);
    currentUser = 'worker-b';
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
    expect(find.text('No jobs found.'), findsOneWidget);
  });
}

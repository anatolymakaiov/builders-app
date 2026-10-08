import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/screens/job_list_screen.dart';

void main() {
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

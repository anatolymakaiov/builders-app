import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/services/vacancy_invitation_service.dart';
import 'package:test_app/web_app/pages/opportunities/web_opportunities_page.dart';

void main() {
  final vacancy = Job(
    id: 'job-1',
    title: 'Dryliner vacancy',
    trade: 'Dryliner',
    site: 'Manchester site',
    location: 'Manchester M1',
    street: '',
    city: 'Manchester',
    postcode: 'M1',
    rate: 25,
    lat: 0,
    lng: 0,
    description: 'Install drylining systems',
    candidateRequirements: 'CSCS card required',
    requiredDocuments: 'CSCS card',
    additionalInformation: 'Bring PPE',
    companyName: 'Builder Ltd',
    photos: const [],
    jobType: 'hourly',
    duration: '2 weeks',
    weeklyHours: '40',
    startDate: DateTime(2026, 11, 20),
    employmentType: 'contract',
    ownerId: 'employer-1',
  );
  const invitation = VacancyInvitation(
    id: 'invite-1',
    vacancyId: 'job-1',
    workerId: 'worker-1',
    title: 'Dryliner vacancy',
    company: 'Builder Ltd',
    tradeId: 'dryliner',
    generalLocation: 'Manchester',
    status: 'pending',
  );

  testWidgets('narrow opportunity opens detail and its existing job route',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final opened = <String>[];
    final actions = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WebOpportunitiesPage(
          workerId: 'worker-1',
          onOpenJob: opened.add,
          invitations: Stream.value([invitation]),
          respondToInvitation: (item, action) async {
            actions.add(action);
            return 'viewed';
          },
          loadJob: (_) async => vacancy,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Dryliner vacancy'), findsOneWidget);
    expect(find.text('Builder Ltd'), findsOneWidget);
    await tester.tap(find.text('Dryliner vacancy'));
    await tester.pumpAndSettle();
    expect(find.text('Install drylining systems'), findsOneWidget);
    expect(find.text('CSCS card required'), findsOneWidget);
    expect(find.text('Bring PPE'), findsOneWidget);
    expect(find.text('Open Vacancy'), findsOneWidget);
    await tester.tap(find.text('Open Vacancy'));
    expect(actions, ['viewed']);
    expect(opened, ['job-1']);
    expect(tester.takeException(), isNull);
    for (final width in [768.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(find.text('Dryliner vacancy'), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('desktop shows master and selected vacancy detail side by side',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WebOpportunitiesPage(
      workerId: 'worker-1',
      onOpenJob: (_) {},
      invitations: Stream.value([invitation]),
      loadJob: (_) async => vacancy,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Dryliner vacancy'), findsNWidgets(2));
    expect(find.text('Install drylining systems'), findsOneWidget);
    expect(find.text('CSCS card required'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty invitations show a real empty state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WebOpportunitiesPage(
          workerId: 'worker-1',
          onOpenJob: (_) {},
          invitations: Stream.value(const []),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No vacancy invitations yet.'), findsOneWidget);
  });
}

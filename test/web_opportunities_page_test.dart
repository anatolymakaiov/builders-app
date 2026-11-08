import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/services/vacancy_invitation_service.dart';
import 'package:test_app/web_app/pages/opportunities/web_opportunities_page.dart';
import 'package:test_app/web_app/pages/jobs/web_worker_vacancy_card.dart';
import 'package:test_app/web_app/widgets/web_remote_image.dart';

void main() {
  final vacancy = Job(
    id: 'job-1',
    title: 'Dryliner vacancy',
    trade: 'Dryliner',
    site: 'Manchester site',
    location: 'Manchester M1',
    street: '12 Example Road',
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
  final invitation = VacancyInvitation(
    id: 'invite-1',
    vacancyId: 'job-1',
    workerId: 'worker-1',
    title: 'Dryliner vacancy',
    company: 'Builder Ltd',
    tradeId: 'dryliner',
    generalLocation: 'Manchester',
    status: 'pending',
    createdAt: DateTime(2026, 11, 8),
  );
  const customInvitation = VacancyInvitation(
    id: 'invite-2',
    vacancyId: 'job-2',
    workerId: 'worker-1',
    title: 'Electrician vacancy',
    company: 'Second Builder',
    tradeId: 'electrician',
    generalLocation: 'Leeds',
    status: 'pending',
    message: 'Please review our site opportunity.',
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
    expect(find.text('Dryliner'), findsOneWidget);
    expect(find.byType(WebWorkerVacancyCard), findsOneWidget);
    expect(find.byType(WebCircleImage), findsOneWidget);
    expect(find.text('12 Example Road, Manchester, M1'), findsOneWidget);
    expect(find.text('Builder Ltd'), findsOneWidget);
    await tester.tap(find.text('Dryliner'));
    await tester.pumpAndSettle();
    expect(find.text('Opportunity Summary'), findsOneWidget);
    expect(find.textContaining('Received'), findsWidgets);
    expect(find.text('Install drylining systems'), findsNothing);
    expect(find.text('CSCS card required'), findsNothing);
    expect(find.text('Bring PPE'), findsNothing);
    expect(find.text('Open Vacancy'), findsOneWidget);
    expect(find.text('40 hours/week'), findsOneWidget);
    expect(find.text('£25/hour'), findsOneWidget);
    await tester.tap(find.text('Open Vacancy'));
    expect(actions, ['viewed']);
    expect(opened, ['job-1']);
    expect(tester.takeException(), isNull);
    for (final width in [768.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(find.text('Dryliner'), findsWidgets);
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
    expect(find.text('Dryliner'), findsNWidgets(2));
    expect(find.text('Dryliner vacancy'), findsNothing);
    expect(find.text('Manchester site'), findsNothing);
    expect(find.text('Engagement'), findsNothing);
    for (final label in [
      'Received',
      'Company',
      'Trade',
      'Address',
      'Pay',
      'Start',
      'Working hours',
      'Duration',
      'Status'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Opportunity Summary'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Invitation')).dy,
        lessThan(tester.getTopLeft(find.text('Open Vacancy')).dy));
    expect(tester.getTopLeft(find.text('Open Vacancy')).dy,
        lessThan(tester.getTopLeft(find.text('Opportunity Summary')).dy));
    expect(find.text('Install drylining systems'), findsNothing);
    expect(find.text('CSCS card required'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop cards select different details without navigation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WebOpportunitiesPage(
          workerId: 'worker-1',
          workerName: 'John Smith',
          onOpenJob: opened.add,
          invitations: Stream.value([invitation, customInvitation]),
          loadJob: (item) async => item.id == invitation.id ? vacancy : null,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('opportunity:invite-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('opportunity:invite-2')), findsOneWidget);
    Container card(String id) => tester.widget<Container>(
          find
              .descendant(
                of: find.byKey(ValueKey('opportunity:$id')),
                matching: find.byType(Container),
              )
              .first,
        );
    expect((card('invite-1').decoration! as BoxDecoration).color,
        const Color(0xFFEAF5FC));
    expect(find.textContaining('Hi John,'), findsOneWidget);
    expect(find.text('Please review our site opportunity.'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('opportunity:invite-2')));
    await tester.pumpAndSettle();
    expect((card('invite-2').decoration! as BoxDecoration).color,
        const Color(0xFFEAF5FC));
    expect(find.text('Please review our site opportunity.'), findsOneWidget);
    expect(find.text('Vacancy details are unavailable.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Open Vacancy'),
            )
            .onPressed,
        isNull);
    expect(opened, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('saved invitation text takes priority over generated greeting', () {
    expect(
        webOpportunityInvitationText(customInvitation,
            workerName: 'John Smith'),
        'Please review our site opportunity.');
    expect(webOpportunityInvitationText(invitation, workerName: 'John Smith'),
        "Hi John,\n\nI'd like to invite you to consider this vacancy.");
    expect(webOpportunityInvitationText(invitation, workerName: 'Worker'),
        "I'd like to invite you to consider this vacancy.");
    expect(webOpportunityInvitationText(invitation),
        "I'd like to invite you to consider this vacancy.");
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

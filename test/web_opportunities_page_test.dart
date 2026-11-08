import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/services/vacancy_invitation_service.dart';
import 'package:test_app/web_app/pages/opportunities/web_opportunities_page.dart';
import 'package:test_app/web_app/pages/jobs/web_worker_vacancy_card.dart';
import 'package:test_app/web_app/widgets/web_remote_image.dart';
import 'package:test_app/web_app/services/web_profile_data_service.dart';

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
          loadWorkerFirstName: (_) async => 'Anthony',
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
      loadWorkerFirstName: (_) async => 'Anthony',
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
          loadWorkerFirstName: (_) async => 'John',
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
    expect(webOpportunityInvitationText(customInvitation, firstName: 'Anthony'),
        'Please review our site opportunity.');
    expect(webOpportunityInvitationText(invitation, firstName: 'Anthony'),
        "Hi Anthony,\n\nI'd like to invite you to consider this vacancy.");
    expect(webOpportunityInvitationText(invitation, firstName: 'John'),
        "Hi John,\n\nI'd like to invite you to consider this vacancy.");
    for (final missing in <String?>[
      null,
      '',
      '   ',
      'Worker',
      'User',
      'null',
      'undefined'
    ]) {
      expect(webOpportunityInvitationText(invitation, firstName: missing),
          "Hi,\n\nI'd like to invite you to consider this vacancy.");
    }
    expect(webOpportunityInvitationText(invitation, firstName: '  Anthony  '),
        "Hi Anthony,\n\nI'd like to invite you to consider this vacancy.");
    expect(webOpportunityInvitationText(invitation),
        "Hi,\n\nI'd like to invite you to consider this vacancy.");
  });

  test('recipient given name uses explicit profile fields only', () {
    expect(
        const WebProfileData(id: 'anthony', data: {
          'firstName': 'Anthony',
          'registrationFirstName': 'Other',
          'name': 'James Sender',
        }).firstName,
        'Anthony');
    expect(
        const WebProfileData(id: 'john', data: {
          'registrationFirstName': 'John',
          'name': 'James Sender',
        }).firstName,
        'John');
    expect(
        const WebProfileData(id: 'missing', data: {
          'name': 'James Sender',
        }).firstName,
        isEmpty);
  });

  testWidgets('recipient profile loading does not show neutral greeting',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final name = Completer<String?>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WebOpportunitiesPage(
          workerId: 'worker-1',
          onOpenJob: (_) {},
          loadWorkerFirstName: (_) => name.future,
          invitations: Stream.value([invitation]),
          loadJob: (_) async => vacancy,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Loading invitation...'), findsOneWidget);
    expect(find.textContaining('Hi,'), findsNothing);
    name.complete('Anthony');
    await tester.pumpAndSettle();
    expect(find.textContaining('Hi Anthony,'), findsOneWidget);
    expect(find.textContaining('Hi James,'), findsNothing);
  });

  testWidgets('profile failure is not mistaken for a missing first name',
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
          loadWorkerFirstName: (_) async => throw StateError('read failed'),
          invitations: Stream.value([invitation]),
          loadJob: (_) async => vacancy,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Could not load recipient name.'), findsOneWidget);
    expect(find.textContaining('Hi,'), findsNothing);
  });

  testWidgets('custom invitation never loads a recipient name', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WebOpportunitiesPage(
          workerId: 'worker-1',
          onOpenJob: (_) {},
          loadWorkerFirstName: (_) async {
            reads++;
            return 'Anthony';
          },
          invitations: Stream.value([customInvitation]),
          loadJob: (_) async => vacancy,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Please review our site opportunity.'), findsOneWidget);
    expect(reads, 0);
  });

  testWidgets('each invitation uses its own recipient and caches profile read',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final reads = <String>[];
    const johnInvitation = VacancyInvitation(
      id: 'invite-john',
      vacancyId: 'job-2',
      workerId: 'worker-2',
      title: 'Electrician vacancy',
      company: 'Builder Ltd',
      tradeId: 'electrician',
      generalLocation: 'Leeds',
      status: 'pending',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WebOpportunitiesPage(
          workerId: 'worker-1',
          onOpenJob: (_) {},
          loadWorkerFirstName: (uid) async {
            reads.add(uid);
            return uid == 'worker-1' ? 'Anthony' : 'John';
          },
          invitations: Stream.value([invitation, johnInvitation]),
          loadJob: (_) async => vacancy,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hi Anthony,'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('opportunity:invite-john')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hi John,'), findsOneWidget);
    expect(find.textContaining('Hi Anthony,'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('opportunity:invite-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hi Anthony,'), findsOneWidget);
    expect(reads, ['worker-1', 'worker-2']);
  });

  testWidgets('automatic greeting follows the recipient after account switch',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    Future<String?> firstName(String uid) async =>
        uid == 'worker-1' ? 'Anthony' : 'John';
    final secondInvitation = VacancyInvitation(
      id: 'invite-worker-2',
      vacancyId: invitation.vacancyId,
      workerId: 'worker-2',
      title: invitation.title,
      company: invitation.company,
      tradeId: invitation.tradeId,
      generalLocation: invitation.generalLocation,
      status: 'pending',
    );
    Widget page(String workerId) => MaterialApp(
          home: Scaffold(
            body: WebOpportunitiesPage(
              workerId: workerId,
              onOpenJob: (_) {},
              loadWorkerFirstName: firstName,
              invitations: Stream.value([
                workerId == 'worker-1' ? invitation : secondInvitation,
              ]),
              loadJob: (_) async => vacancy,
            ),
          ),
        );

    await tester.pumpWidget(page('worker-1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hi Anthony,'), findsOneWidget);
    expect(find.textContaining('Hi James,'), findsNothing);
    await tester.pumpWidget(page('worker-2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hi John,'), findsOneWidget);
    expect(find.textContaining('Hi Anthony,'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty invitations show a real empty state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WebOpportunitiesPage(
          workerId: 'worker-1',
          loadWorkerFirstName: (_) async => null,
          onOpenJob: (_) {},
          invitations: Stream.value(const []),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No vacancy invitations yet.'), findsOneWidget);
  });
}

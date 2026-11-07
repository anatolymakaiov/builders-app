import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/vacancy_invitation_service.dart';
import 'package:test_app/web_app/pages/opportunities/web_opportunities_page.dart';

void main() {
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

  testWidgets('real invitation opens its existing job route', (tester) async {
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
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Dryliner vacancy'), findsOneWidget);
    expect(find.text('Builder Ltd'), findsOneWidget);
    expect(find.text('Dryliner'), findsOneWidget);
    expect(find.text('Manchester'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    await tester.tap(find.text('View vacancy'));
    await tester.pumpAndSettle();
    expect(actions, ['viewed']);
    expect(opened, ['job-1']);
    expect(tester.takeException(), isNull);
    for (final width in [768.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(find.text('Dryliner vacancy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
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

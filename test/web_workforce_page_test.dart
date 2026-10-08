import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/web_app/pages/workforce/web_workforce_page.dart';
import 'package:test_app/web_app/services/web_sites_service.dart';
import 'package:test_app/web_app/services/workforce_planning_service.dart';
import 'package:test_app/web_app/services/workforce_talent_request.dart';

void main() {
  final sites = [
    const WebSite(id: 'site-a', data: {
      'employerContextId': 'employer-a',
      'name': 'Site A',
      'city': 'Manchester',
      'status': 'active',
    }),
    const WebSite(id: 'site-b', data: {
      'employerContextId': 'employer-a',
      'name': 'Site B',
      'city': 'Salford',
      'status': 'active',
    }),
  ];
  final jobs = [
    Job(
        id: 'vacancy-a',
        title: 'Dryliner',
        trade: 'Dryliner',
        site: 'Site A',
        siteId: 'site-a',
        canonicalRoleId: 'dryliner',
        location: 'Manchester',
        street: '',
        city: 'Manchester',
        postcode: '',
        rate: 25,
        lat: 0,
        lng: 0,
        description: '',
        companyName: 'Employer',
        photos: const [],
        jobType: 'hourly',
        duration: '2 weeks',
        employmentType: 'contract',
        ownerId: 'employer-a',
        moderationStatus: 'approved',
        positions: 3),
  ];
  WorkforcePlan makePlan(String? siteId, String? tradeId) =>
      deriveWorkforcePlan(
          employerId: 'employer-a',
          sites: sites,
          jobs: jobs,
          assignments: const [],
          window: PlanningWindow.nextDays(DateTime.now(), 14),
          now: DateTime.now(),
          siteId: siteId,
          tradeId: tradeId);

  testWidgets('summary, gap and Talent handoff use the selected vacancy',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WorkforceTalentRequest? handoff;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WebWorkforcePage(
      employerId: 'employer-a',
      loadPlan: (
              {required employerId,
              required window,
              required now,
              siteId,
              tradeId}) async =>
          makePlan(siteId, tradeId),
      onFindWorkers: (request) => handoff = request,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Workforce'), findsOneWidget);
    expect(find.text('Staffing Gaps'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    await tester.ensureVisible(find.text('Find Workers'));
    await tester.tap(find.text('Find Workers'));
    expect(handoff?.tradeId, 'dryliner');
    expect(handoff?.location, 'Manchester');
    expect(handoff?.vacancyId, 'vacancy-a');
  });

  testWidgets('Site filter reloads the scoped planning view', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requestedSites = <String?>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WebWorkforcePage(
      employerId: 'employer-a',
      loadPlan: (
          {required employerId,
          required window,
          required now,
          siteId,
          tradeId}) async {
        requestedSites.add(siteId);
        return makePlan(siteId, tradeId);
      },
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workforce-site:')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Site B').last);
    await tester.pumpAndSettle();
    expect(requestedSites.last, 'site-b');
    expect(
        find.text('No open vacancy positions in this period.'), findsOneWidget);
  });

  testWidgets('planning controls fit a portrait browser width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WebWorkforcePage(
      employerId: 'employer-a',
      loadPlan: (
              {required employerId,
              required window,
              required now,
              siteId,
              tradeId}) async =>
          makePlan(siteId, tradeId),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Workforce'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

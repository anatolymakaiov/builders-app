import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/admin/admin_command_service.dart';
import 'package:test_app/web_app/admin/admin_operations_page.dart';
import 'package:test_app/web_app/services/web_admin_profile_service.dart';

class _CommandService extends AdminCommandService {
  final calls = <(AdminOperationalView, String?)>[];

  @override
  Future<AdminCommandPage> load(String adminUid, AdminOperationalView view,
      {String? cursor, int pageSize = 25}) async {
    calls.add((view, cursor));
    if (view == AdminOperationalView.sites) {
      return const AdminCommandPage([
        WebAdminRecord('sites', 'site-1', {
          'name': 'Manchester Tower',
          'city': 'Manchester',
          'employerContextId': 'employer-1',
          'adminVacancyCount': 2,
          'adminWorkforceCount': 4,
        }),
      ], null);
    }
    if (view == AdminOperationalView.subscriptions) {
      return const AdminCommandPage([
        WebAdminRecord('users', 'employer-1', {
          'companyName': 'Build Co',
          'planName': 'Growth',
          'subscriptionStatus': 'active',
          'vacancySlotLimit': 10,
          'usedJobPosts': 2,
          'invitationUsed': 12,
          'invitationLimit': 200,
        }),
      ], null);
    }
    if (cursor != null) {
      return const AdminCommandPage([
        WebAdminRecord('jobs', 'job-2', {
          'title': 'Electrician',
          'ownerId': 'employer-1',
          'siteId': 'site-1',
        }),
      ], null);
    }
    return const AdminCommandPage([
      WebAdminRecord('jobs', 'job-1', {
        'title': 'Dryliner',
        'ownerId': 'employer-1',
        'siteId': 'site-1',
        'positions': 3,
        'filledPositions': 1,
      }),
    ], 'job-1');
  }
}

void main() {
  testWidgets('Admin operations pages without loading the full collection',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _CommandService();
    WebAdminRecord? opened;
    String? employer;
    String? site;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminOperationsPage(
          adminUid: 'admin-1',
          service: service,
          onOpenRecord: (row) => opened = row,
          onOpenUser: (id) => employer = id,
          onOpenSite: (id) => site = id,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Dryliner'), findsOneWidget);
    expect(service.calls, [(AdminOperationalView.jobs, null)]);
    await tester.tap(find.text('Employer').first);
    expect(employer, 'employer-1');
    await tester.tap(find.text('Site').first);
    expect(site, 'site-1');
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Electrician'), findsOneWidget);
    expect(service.calls.last, (AdminOperationalView.jobs, 'job-1'));
    await tester.tap(find.text('Dryliner'));
    expect(opened?.id, 'job-1');
    await tester.tap(find.text('Sites').first);
    await tester.pumpAndSettle();
    expect(find.text('Manchester Tower'), findsOneWidget);
    expect(find.textContaining('2 open vacancies'), findsOneWidget);
    expect(service.calls.last, (AdminOperationalView.sites, null));
    await tester.tap(find.text('Subscriptions').first);
    await tester.pumpAndSettle();
    expect(find.text('Build Co'), findsOneWidget);
    expect(find.textContaining('2/10 vacancy slots'), findsOneWidget);
    expect(find.textContaining('12/200 invitations'), findsOneWidget);
    await tester.tap(find.text('Build Co'));
    expect(employer, 'employer-1');
  });
}

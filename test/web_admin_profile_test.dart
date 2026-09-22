import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/pages/profile/web_admin_profile_page.dart';
import 'package:test_app/web_app/services/web_admin_profile_service.dart';
import 'package:test_app/web_app/services/web_admin_report_summary.dart';
import 'package:test_app/web_app/shell/web_profile_destination.dart';

void main() {
  test('own administrator resolves to the admin Web profile', () {
    expect(
        resolveWebProfileDestination(
          viewerUid: 'admin-1',
          viewerRole: 'admin',
          profileUid: 'admin-1',
          profileRole: 'admin',
        ),
        WebProfileDestination.admin);
  });

  test('worker and employer retain their existing Web profiles', () {
    for (final role in ['worker', 'employer']) {
      expect(
          resolveWebProfileDestination(
            viewerUid: role,
            viewerRole: role,
            profileUid: role,
            profileRole: role,
          ),
          WebProfileDestination.standard);
    }
  });

  test('other users cannot route into an administrator profile', () {
    expect(
        resolveWebProfileDestination(
          viewerUid: 'worker-1',
          viewerRole: 'worker',
          profileUid: 'admin-1',
          profileRole: 'admin',
        ),
        WebProfileDestination.unavailable);
    expect(
        resolveWebProfileDestination(
          viewerUid: 'admin-1',
          viewerRole: 'admin',
          profileUid: 'admin-2',
          profileRole: 'admin',
        ),
        WebProfileDestination.unavailable);
  });

  test('administrator actions require matching authenticated admin UID', () {
    expect(
        webAdminRoleAllowsAccess(
          authenticatedUid: 'admin-1',
          requestedUid: 'admin-1',
          role: 'admin',
        ),
        isTrue);
    expect(
        webAdminRoleAllowsAccess(
          authenticatedUid: 'worker-1',
          requestedUid: 'worker-1',
          role: 'worker',
        ),
        isFalse);
    expect(
        webAdminRoleAllowsAccess(
          authenticatedUid: 'admin-1',
          requestedUid: 'admin-2',
          role: 'admin',
        ),
        isFalse);
    expect(
        webAdminRoleAllowsAccess(
          authenticatedUid: null,
          requestedUid: 'admin-1',
          role: 'admin',
        ),
        isFalse);
  });

  test('admin search matches formatted phone, company and vacancy text', () {
    const company = WebAdminRecord('users', 'employer-1', {
      'companyName': 'Build & Fix Ltd',
      'phone': '+44 7700 900123',
    });
    const job = WebAdminRecord('jobs', 'job-1', {
      'title': 'Ceiling Fixer',
      'postcode': 'SW1A 1AA',
    });
    expect(webAdminSearchMatches(company, '7700900123'), isTrue);
    expect(webAdminSearchMatches(company, 'build fix'), isTrue);
    expect(webAdminSearchMatches(job, 'ceiling'), isTrue);
    expect(webAdminSearchMatches(job, 'sw1a1aa'), isTrue);
    expect(webAdminSearchMatches(job, 'unrelated'), isFalse);
  });

  test('financial summary deduplicates companies and excludes held accounts',
      () {
    final records = <WebAdminRecord>[
      const WebAdminRecord('plans', 'starter', {'price': 49}),
      const WebAdminRecord('users', 'owner-1', {
        'role': 'employer',
        'companyId': 'company-a',
        'billing': {
          'status': 'active',
          'planId': 'starter',
          'paymentMode': 'direct_debit'
        },
      }),
      const WebAdminRecord('users', 'owner-2', {
        'role': 'employer',
        'companyId': 'company-a',
        'billing': {'status': 'active', 'planId': 'starter'},
      }),
      const WebAdminRecord('users', 'owner-3', {
        'role': 'employer',
        'companyId': 'company-b',
        'moderationHold': true,
        'billing': {'status': 'active', 'planId': 'starter'},
      }),
      const WebAdminRecord('payment_requests', 'paid-1', {
        'status': 'paid',
        'amount': 49,
        'providerPaymentId': 'provider-1',
        'updatedAt': '2026-09-15T10:00:00Z',
      }),
    ];
    final summary = WebAdminReportSummary.fromRecords(records,
        now: DateTime.utc(2026, 9, 22));
    expect(summary.activeEmployers, 1);
    expect(summary.billableCompanies, 1);
    expect(summary.expectedMonthlyRevenue, 49);
    expect(summary.receivedMonthlyRevenue, 49);
  });

  testWidgets('admin actions are rendered only after access is confirmed',
      (tester) async {
    Future<void> show(Future<bool> access) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: WebAdminProfileAccessGate(
            access: access,
            onClose: () {},
            child: const FilledButton(
                onPressed: null, child: Text('Hold profile')),
          )),
        ));

    await show(Future.value(false));
    await tester.pumpAndSettle();
    expect(find.text('Hold profile'), findsNothing);
    expect(find.text('Administrator access required.'), findsOneWidget);

    await show(Future.value(true));
    await tester.pumpAndSettle();
    expect(find.text('Hold profile'), findsOneWidget);
  });
}

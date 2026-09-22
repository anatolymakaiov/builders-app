import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/billing_service.dart';
import 'web_admin_profile_service.dart';

class WebAdminReportSummary {
  const WebAdminReportSummary({
    required this.activeWorkers,
    required this.activeEmployers,
    required this.billableCompanies,
    required this.directDebitCompanies,
    required this.expectedMonthlyRevenue,
    required this.receivedMonthlyRevenue,
    required this.pendingPaymentRequests,
    required this.currentMonthUsers,
    required this.previousMonthUsers,
  });

  final int activeWorkers;
  final int activeEmployers;
  final int billableCompanies;
  final int directDebitCompanies;
  final double expectedMonthlyRevenue;
  final double receivedMonthlyRevenue;
  final int pendingPaymentRequests;
  final int currentMonthUsers;
  final int previousMonthUsers;

  factory WebAdminReportSummary.fromRecords(
    List<WebAdminRecord> records, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final monthStart = DateTime(today.year, today.month);
    final previousStart = DateTime(today.year, today.month - 1);
    final users = records.where((item) => item.collection == 'users').toList();
    final payments =
        records.where((item) => item.collection == 'payment_requests').toList();
    final prices = <String, double>{
      for (final plan in records.where((item) => item.collection == 'plans'))
        plan.id: BillingService.readMoney(plan.data['price']),
    };
    final companies = <String, WebAdminRecord>{};
    for (final user in users.where((item) => item.data['role'] == 'employer')) {
      final key = (user.data['companyId'] ??
              user.data['uid'] ??
              user.data['userId'] ??
              user.id)
          .toString()
          .trim()
          .toLowerCase();
      if (key.isNotEmpty) companies[key] = user;
    }
    final activeCompanies = companies.values.where(_active).toList();
    final billable = activeCompanies.where(_billable).toList();
    double expected = 0;
    for (final company in billable) {
      final billing = BillingService.billingFromUserData(company.data);
      final planId =
          (billing['activePlanId'] ?? billing['planId'])?.toString() ?? '';
      expected += prices[planId] ?? 0;
    }
    double received = 0;
    for (final payment in payments) {
      final data = payment.data;
      final status = data['status']?.toString().toLowerCase() ?? '';
      final paid = status == 'paid' ||
          data['paymentStatus']?.toString().toLowerCase() == 'paid' ||
          data['invoiceStatus']?.toString().toLowerCase() == 'paid';
      final paidAt = _date(
          data['paidAt'] ?? data['confirmedAt'] ?? data['providerPaidAt']);
      final hasReference = (data['providerPaymentId'] ??
                  data['transactionId'] ??
                  data['paymentIntentId'])
              ?.toString()
              .trim()
              .isNotEmpty ==
          true;
      final paymentDate =
          paidAt ?? _date(data['updatedAt']) ?? _date(data['createdAt']);
      if (paid &&
          (paidAt != null || hasReference) &&
          paymentDate != null &&
          !paymentDate.isBefore(monthStart) &&
          paymentDate.isBefore(DateTime(today.year, today.month + 1))) {
        final amount = BillingService.readMoney(
            data['amount'] ?? data['total'] ?? data['price']);
        received +=
            amount > 0 ? amount : prices[data['planId']?.toString() ?? ''] ?? 0;
      }
    }
    int registered(DateTime start, DateTime end) => users.where((item) {
          final date = _date(item.data['createdAt']);
          return date != null && !date.isBefore(start) && date.isBefore(end);
        }).length;
    return WebAdminReportSummary(
      activeWorkers: users
          .where((item) => item.data['role'] == 'worker' && _active(item))
          .length,
      activeEmployers: activeCompanies.length,
      billableCompanies: billable.length,
      directDebitCompanies: billable.where((item) {
        final billing = BillingService.billingFromUserData(item.data);
        return billing['directDebitEnabled'] == true ||
            billing['paymentMode']
                    ?.toString()
                    .toLowerCase()
                    .contains('direct_debit') ==
                true;
      }).length,
      expectedMonthlyRevenue: expected,
      receivedMonthlyRevenue: received,
      pendingPaymentRequests:
          payments.where((item) => item.data['status'] == 'pending').length,
      currentMonthUsers:
          registered(monthStart, DateTime(today.year, today.month + 1)),
      previousMonthUsers: registered(previousStart, monthStart),
    );
  }

  static bool _active(WebAdminRecord item) {
    final data = item.data;
    final status = data['status']?.toString().toLowerCase() ?? '';
    return data['deleted'] != true &&
        data['accountDeleted'] != true &&
        data['anonymised'] != true &&
        data['active'] != false &&
        data['moderationHold'] != true &&
        data['profileSuspended'] != true &&
        data['profileHold'] != true &&
        data['accountOnHold'] != true &&
        !{'deleted', 'suspended', 'on_hold', 'cancelled', 'inactive'}
            .contains(status);
  }

  static bool _billable(WebAdminRecord item) {
    final billing = BillingService.billingFromUserData(item.data);
    String value(String key) =>
        billing[key]?.toString().trim().toLowerCase() ?? '';
    final blocked = {
      'payment_required',
      'billing_required',
      'suspended',
      'cancelled',
      'expired',
      'failed',
      'rejected',
      'deleted'
    };
    final planId =
        (billing['activePlanId'] ?? billing['planId'])?.toString() ?? '';
    return planId.isNotEmpty &&
        (value('status') == 'active' ||
            value('billingPlanStatus') == 'approved') &&
        !blocked.contains(value('status')) &&
        !blocked.contains(value('subscriptionStatus')) &&
        !blocked.contains(value('paymentStatus'));
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/billing_service.dart';

void main() {
  test('next GoCardless charge date is available to Billing presentation', () {
    final status = BillingService.normalizeBillingDateFields({
      'firstPaymentDate': '2026-09-01',
      'nextChargeDate': '2026-10-01',
    });

    expect(BillingService.formatDate(status['firstPaymentDate']),
        '1 Sep 2026');
    expect(BillingService.formatDate(status['nextChargeDate']),
        '1 Oct 2026');
  });
}

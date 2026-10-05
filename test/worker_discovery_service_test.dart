import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/worker_discovery_service.dart';

void main() {
  test('safe worker model parses only discovery fields', () {
    final worker = WorkerDiscoveryProfile.fromMap('worker-1', {
      'displayNameShort': 'Anthony M.',
      'primaryTradeId': 'dryliner',
      'tradeIds': ['dryliner'],
      'rating': 4.7,
      'availabilityStatus': 'unknown',
      'allowVacancyInvites': false,
      'generalArea': 'Manchester',
      'phone': 'private',
      'email': 'private@example.com',
      'addressLine1': '1 Private Street',
      'lat': 53.481,
    });
    expect(worker.workerId, 'worker-1');
    expect(worker.displayNameShort, 'Anthony M.');
    expect(worker.tradeIds, ['dryliner']);
    expect(worker.rating, 4.7);
    expect(worker.availabilityStatus, 'unknown');
    expect(worker.allowVacancyInvites, isFalse);
    expect(worker.generalArea, 'Manchester');
  });
}

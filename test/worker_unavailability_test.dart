import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/worker_unavailability_service.dart';

void main() {
  final now = DateTime.utc(2026, 10, 6);
  test('worker unavailable period date and type validation', () {
    bool valid(DateTime start, DateTime end, String type, [String note = '']) =>
        WorkerUnavailabilityService.validPeriod(start, end, type, note, now);
    expect(
        valid(DateTime.utc(2026, 10, 7), DateTime.utc(2026, 10, 9), 'holiday'),
        isTrue);
    expect(
        valid(DateTime.utc(2026, 10, 9), DateTime.utc(2026, 10, 7), 'holiday'),
        isFalse);
    expect(
        valid(DateTime.utc(2026, 10, 7), DateTime.utc(2026, 10, 9), 'medical'),
        isFalse);
    expect(
        valid(DateTime.utc(2026, 10, 7), DateTime.utc(2026, 10, 9), 'personal',
            'x' * 501),
        isFalse);
  });
}

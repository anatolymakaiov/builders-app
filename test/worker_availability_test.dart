import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/worker_availability_service.dart';
import 'package:test_app/services/registration_validation_service.dart';

void main() {
  test('legacy worker defaults to Open to Work', () {
    expect(WorkerAvailabilityService.fromProfile({}),
        WorkerAvailability.openToWork);
    expect(
        WorkerAvailabilityService.label(
            WorkerAvailabilityService.fromProfile({})),
        'Open to Work');
  });

  test('Busy and Open to Work use stable Firestore values', () {
    expect(WorkerAvailabilityService.value(WorkerAvailability.busy), 'busy');
    expect(
        WorkerAvailabilityService.fromProfile(
            {WorkerAvailabilityService.field: 'busy'}),
        WorkerAvailability.busy);
    expect(WorkerAvailabilityService.value(WorkerAvailability.openToWork),
        'open_to_work');
  });

  test('new worker registration stores the explicit default', () {
    const details = PendingRegistrationDetails(
      email: 'worker@example.com',
      role: 'worker',
      registrationName: 'Worker',
      phone: '+440000000000',
      normalizedPhone: '+440000000000',
    );
    expect(details.toUserDocument()[WorkerAvailabilityService.field],
        'open_to_work');
  });
}

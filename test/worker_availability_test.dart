import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/registration_validation_service.dart';
import 'package:test_app/services/worker_availability_service.dart';

void main() {
  final now = DateTime.utc(2026, 10, 5, 12);

  Map<String, dynamic> saved(
    WorkerAvailability status, {
    DateTime? from,
    bool invites = false,
  }) =>
      WorkerAvailabilityService.updateFields(
        WorkerAvailabilitySelection(
          status: status,
          availableFrom: from,
          allowVacancyInvites: invites,
        ),
        now: now,
      );

  test('unconfirmed and new workers are not available by default', () {
    expect(
        WorkerAvailabilityService.fromProfile({}), WorkerAvailability.unknown);
    expect(WorkerAvailabilityService.allowsInvites({}), isFalse);
    expect(WorkerAvailabilityService.shouldPrompt({}, now), isTrue);
    const details = PendingRegistrationDetails(
      email: 'worker@example.com',
      role: 'worker',
      registrationName: 'Worker',
      phone: '+440000000000',
      normalizedPhone: '+440000000000',
    );
    expect(
        details.toUserDocument().containsKey(WorkerAvailabilityService.field),
        isFalse);
  });

  test(
      'legacy auto-filled status requires confirmation; new writes are canonical',
      () {
    expect(
      WorkerAvailabilityService.fromProfile(
          {'availabilityStatus': 'open_to_work'}),
      WorkerAvailability.unknown,
    );
    expect(saved(WorkerAvailability.availableNow)['availabilityStatus'],
        'available_now');
  });

  test('available now clears old date and records confirmation', () {
    final fields =
        saved(WorkerAvailability.availableNow, from: DateTime(2027, 1, 1));
    expect(fields['availableFrom'], isNull);
    expect(fields['availabilityConfirmedAt'], Timestamp.fromDate(now));
    expect(fields['availabilityUpdatedAt'], Timestamp.fromDate(now));
  });

  test('available from requires a nonpast date and preserves exact day', () {
    expect(() => saved(WorkerAvailability.availableFrom), throwsArgumentError);
    expect(
      () =>
          saved(WorkerAvailability.availableFrom, from: DateTime(2026, 10, 4)),
      throwsArgumentError,
    );
    final fields = saved(WorkerAvailability.availableFrom,
        from: DateTime(2026, 10, 21, 18));
    expect(WorkerAvailabilityService.availableFrom(fields),
        DateTime.utc(2026, 10, 21));
    expect(WorkerAvailabilityService.profileLabel(fields),
        'Available from 21 Oct 2026');
  });

  test('public unavailable projection has a readable label', () {
    expect(
        WorkerAvailabilityService.profileLabel({
          'availabilityStatus': 'unavailable',
          'availableFrom': Timestamp.fromDate(DateTime.utc(2026, 10, 21)),
        }),
        'Unavailable until 20 Oct 2026');
    expect(
        WorkerAvailabilityService.profileLabel({
          'availabilityStatus': 'busy',
          'availableFrom': Timestamp.fromDate(DateTime.utc(2026, 10, 21)),
        }),
        'Busy until 20 Oct 2026');
  });

  test('busy and not looking clear obsolete dates', () {
    for (final status in [
      WorkerAvailability.busy,
      WorkerAvailability.notLooking
    ]) {
      final fields = saved(status, from: DateTime(2027, 1, 1));
      expect(fields['availabilityStatus'],
          WorkerAvailabilityService.value(status));
      expect(fields['availableFrom'], isNull);
    }
  });

  test('invitation permission is independent of availability', () {
    expect(saved(WorkerAvailability.busy, invites: true)['allowVacancyInvites'],
        isTrue);
    expect(
        saved(WorkerAvailability.availableNow,
            invites: false)['allowVacancyInvites'],
        isFalse);
  });

  test('available now check-in waits seven days, then becomes due', () {
    final profile = saved(WorkerAvailability.availableNow);
    expect(
        WorkerAvailabilityService.shouldPrompt(
            profile, now.add(const Duration(days: 6))),
        isFalse);
    expect(
        WorkerAvailabilityService.shouldPrompt(
            profile, now.add(const Duration(days: 7))),
        isTrue);
  });

  test('busy waits ten days; not looking waits thirty days', () {
    final busy = saved(WorkerAvailability.busy);
    final notLooking = saved(WorkerAvailability.notLooking);
    expect(
        WorkerAvailabilityService.shouldPrompt(
            busy, now.add(const Duration(days: 9))),
        isFalse);
    expect(
        WorkerAvailabilityService.shouldPrompt(
            busy, now.add(const Duration(days: 10))),
        isTrue);
    expect(
        WorkerAvailabilityService.shouldPrompt(
            notLooking, now.add(const Duration(days: 29))),
        isFalse);
    expect(
        WorkerAvailabilityService.shouldPrompt(
            notLooking, now.add(const Duration(days: 30))),
        isTrue);
  });

  test('future availability is not repeatedly prompted until date approaches',
      () {
    final profile =
        saved(WorkerAvailability.availableFrom, from: DateTime(2026, 10, 21));
    expect(
        WorkerAvailabilityService.shouldPrompt(
            profile, now.add(const Duration(days: 10))),
        isFalse);
    expect(
        WorkerAvailabilityService.shouldPrompt(
            profile, DateTime.utc(2026, 10, 18)),
        isTrue);
    expect(
        WorkerAvailabilityService.shouldPrompt(
            profile, DateTime.utc(2026, 10, 21)),
        isTrue);
    final reconfirmed = WorkerAvailabilityService.updateFields(
      WorkerAvailabilitySelection(
        status: WorkerAvailability.availableFrom,
        availableFrom: DateTime(2026, 10, 21),
        allowVacancyInvites: false,
      ),
      now: DateTime.utc(2026, 10, 18),
    );
    expect(
        WorkerAvailabilityService.shouldPrompt(
            reconfirmed, DateTime.utc(2026, 10, 19)),
        isFalse);
    expect(
        WorkerAvailabilityService.shouldPrompt(
            reconfirmed, DateTime.utc(2026, 10, 21)),
        isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/screens/employer_dashboard_screen.dart';
import 'package:test_app/services/offer_acceptance_service.dart';

Job job(
        {String id = 'job',
        int positions = 1,
        int filled = 0,
        String status = 'active'}) =>
    Job(
      id: id,
      title: 'Dryliner',
      trade: 'Dryliner',
      site: 'Site',
      location: 'Manchester',
      street: '',
      city: 'Manchester',
      postcode: 'M1 1AA',
      rate: 25,
      lat: 0,
      lng: 0,
      description: '',
      companyName: 'Company',
      photos: const [],
      jobType: 'hourly',
      duration: '',
      employmentType: '',
      ownerId: 'employer',
      moderationStatus: 'approved',
      status: status,
      positions: positions,
      filledPositions: filled,
    );

void main() {
  test('one unfilled position is open', () {
    expect(job().remainingPositions, 1);
    expect(job().isOpenForHiring, isTrue);
  });

  test('accepted final position is filled and no longer open', () {
    final filled = job(filled: 1);
    expect(filled.remainingPositions, 0);
    expect(filled.isFullyFilled, isTrue);
    expect(filled.isOpenForHiring, isFalse);
  });

  test('partially filled vacancy keeps remaining slots', () {
    expect(job(positions: 5, filled: 3).remainingPositions, 2);
    expect(job(positions: 5, filled: 3).isOpenForHiring, isTrue);
  });

  test('open count excludes fully filled and closed vacancies', () {
    final jobs = [job(), job(filled: 1), job(status: 'closed')];
    expect(jobs.where((entry) => entry.isOpenForHiring).length, 1);
  });

  test('employer market excludes filled own jobs but owner history keeps them',
      () {
    final open = job(id: 'open');
    final filled = job(id: 'filled', filled: 1);
    final ownJobs = [open, filled];
    final market = mergeEmployerVisibleJobs(
      publicJobs: [open],
      ownerJobs: ownJobs,
    );
    expect(market.length, 1);
    expect(market.single.isOpenForHiring, isTrue);
    expect(ownJobs.length, 2);
  });

  test('accepted offer uses selected workers once per application', () {
    expect(
        OfferAcceptanceService.applicationSlotCount({
          'offer': {
            'selectedWorkerIds': ['a', 'a', 'b']
          },
          'members': ['a', 'b', 'c'],
        }),
        2);
  });

  test('accepted application markers prevent a second slot update', () {
    expect(
        OfferAcceptanceService.slotAlreadyApplied(
            {'slotDecrementApplied': true}, {}, 'application-1'),
        isTrue);
    expect(
        OfferAcceptanceService.slotAlreadyApplied({}, {
          'slotDecrementApplicationIds': ['application-1']
        }, 'application-1'),
        isTrue);
    expect(
        OfferAcceptanceService.slotAlreadyApplied({}, {
          'slotDecrementApplicationIds': ['application-2']
        }, 'application-1'),
        isFalse);
  });
}

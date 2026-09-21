import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/worker_review_service.dart';

void main() {
  test('eligible engagement preserves the authoritative application context',
      () {
    final engagement = ReviewEngagement.fromMap({
      'applicationId': 'application-1',
      'employerId': 'employer-1',
      'employerName': 'Build Co',
      'jobTitle': 'Ceiling Fixer',
      'requestStatus': '',
    });

    expect(engagement.applicationId, 'application-1');
    expect(engagement.employerName, 'Build Co');
    expect(engagement.jobTitle, 'Ceiling Fixer');
    expect(engagement.canRequest, isTrue);
  });

  test('review lifecycle exposes only the action for the current state', () {
    EmployerReviewRequest request(String status) =>
        EmployerReviewRequest.fromMap({
          'id': 'review-1',
          'workerId': 'worker-1',
          'employerId': 'employer-1',
          'status': status,
          'rating': 5,
          'review': 'Reliable worker',
        });

    expect(request('requested').awaitingEmployer, isTrue);
    expect(request('requested').awaitingWorker, isFalse);
    expect(request('responded').awaitingWorker, isTrue);
    expect(request('published').awaitingEmployer, isFalse);
    expect(request('declined').awaitingWorker, isFalse);
  });
}

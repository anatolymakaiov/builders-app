import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/worker_job_application_status.dart';

void main() {
  test('no application means Not Applied for every vacancy', () {
    final ids = WorkerJobApplicationStatus.appliedJobIds(
      uid: 'worker-a',
      workerApplications: const [],
      teamApplications: const {},
      teamIds: const {},
    );
    expect(ids.contains('job-a'), isFalse);
    expect(ids.contains('job-b'), isFalse);
  });

  test('individual applications and ongoing offer states remain Applied', () {
    final ids = WorkerJobApplicationStatus.appliedJobIds(
      uid: 'worker-a',
      workerApplications: const [
        {'jobId': 'job-a', 'workerId': 'worker-a', 'status': 'pending'},
        {'jobId': 'job-b', 'workerId': 'worker-a', 'status': 'negotiation'},
        {'jobId': 'job-c', 'workerId': 'worker-a', 'status': 'offer_sent'},
        {'jobId': 'job-d', 'workerId': 'worker-a', 'status': 'offer_accepted'},
        {'jobId': 'job-e', 'workerId': 'worker-a', 'status': 'withdrawn'},
      ],
      teamApplications: const {},
      teamIds: const {},
    );
    expect(ids, {'job-a', 'job-b', 'job-c', 'job-d'});
  });

  test('current team member sees legacy and current team applications', () {
    final teams = WorkerJobApplicationStatus.teamIdsForWorker('worker-a', {
      'team-one': {
        'memberIds': ['worker-a']
      },
      'team-two': {
        'members': [
          {'userId': 'worker-a'}
        ]
      },
      'team-left': {
        'memberStatuses': {'worker-a': 'left'}
      },
    });
    final ids = WorkerJobApplicationStatus.appliedJobIds(
      uid: 'worker-a',
      workerApplications: const [],
      teamApplications: const {
        'team-one': [
          {
            'jobId': 'job-a',
            'teamId': 'team-one',
            'type': 'team',
            'status': 'pending'
          },
          {
            'jobId': 'job-d',
            'teamId': 'team-one',
            'type': 'team',
            'status': 'withdrawn'
          },
        ],
        'team-two': [
          {
            'jobId': 'job-b',
            'teamId': 'team-two',
            'applicationType': 'team',
            'status': 'offer_accepted'
          },
        ],
        'team-left': [
          {'jobId': 'job-c', 'teamId': 'team-left', 'type': 'team'},
        ],
      },
      teamIds: teams,
    );
    expect(ids, {'job-a', 'job-b'});
  });

  test('application state is computed for the current uid only', () {
    const apps = [
      {'jobId': 'job-a', 'workerId': 'worker-a', 'status': 'pending'},
      {'jobId': 'job-b', 'workerId': 'worker-b', 'status': 'pending'},
    ];
    Set<String> forUser(String uid) => WorkerJobApplicationStatus.appliedJobIds(
          uid: uid,
          workerApplications: apps,
          teamApplications: const {},
          teamIds: const {},
        );
    expect(forUser('worker-a'), {'job-a'});
    expect(forUser('worker-b'), {'job-b'});
  });
}

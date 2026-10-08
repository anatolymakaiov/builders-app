import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/services/worker_assignment_service.dart';
import 'package:test_app/web_app/services/web_sites_service.dart';
import 'package:test_app/web_app/services/workforce_planning_service.dart';
import 'package:test_app/web_app/services/workforce_talent_request.dart';

void main() {
  final now = DateTime(2026, 10, 7, 12);
  final window = PlanningWindow.nextDays(now, 14);
  final sites = [
    const WebSite(id: 'site-a', data: {
      'employerContextId': 'employer-a',
      'name': 'Site A',
      'status': 'active',
      'city': 'Manchester',
    }),
    const WebSite(id: 'site-b', data: {
      'employerContextId': 'employer-a',
      'name': 'Site B',
      'status': 'active',
      'city': 'Salford',
    }),
    const WebSite(id: 'foreign', data: {
      'employerContextId': 'employer-b',
      'name': 'Other Site',
      'status': 'active',
    }),
  ];

  WorkforcePlan plan(
          {List<Job> jobs = const [],
          List<WorkerAssignment> assignments = const [],
          String? siteId,
          String? tradeId}) =>
      deriveWorkforcePlan(
          employerId: 'employer-a',
          sites: sites,
          jobs: jobs,
          assignments: assignments,
          window: window,
          now: now,
          siteId: siteId,
          tradeId: tradeId);

  test('open positions are not reduced twice by accepted assignments', () {
    final result = plan(jobs: [
      job('a', positions: 5, filled: 3)
    ], assignments: [
      assignment('one', 'worker-1', 'site-a', start: DateTime(2026, 10, 1))
    ]);
    expect(result.openVacancies, 1);
    expect(result.gapCount, 2);
    expect(result.gaps.single.currentWorkers, 1);
    expect(
        result.siteSummaries
            .firstWhere((s) => s.siteId == 'site-a')
            .openPositions,
        2);
  });

  test('closed, unapproved, filled and other-employer jobs are excluded', () {
    final result = plan(jobs: [
      job('filled', positions: 2, filled: 2),
      job('closed', status: 'closed'),
      job('review', moderation: 'pending_review'),
      job('foreign', owner: 'employer-b'),
    ]);
    expect(result.openVacancies, 0);
    expect(result.gapCount, 0);
    expect(result.sites.length, 2);
  });

  test('counts current, starts, finishes and projected headcount', () {
    final result = plan(assignments: [
      assignment('current', 'worker-1', 'site-a',
          start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 9)),
      assignment('incoming', 'worker-2', 'site-a',
          start: DateTime(2026, 10, 8)),
      assignment('cancelled', 'worker-3', 'site-a',
          start: DateTime(2026, 10, 8), status: 'cancelled'),
      assignment('completed', 'worker-4', 'site-a',
          start: DateTime(2026, 10, 1), status: 'completed'),
    ]);
    expect(result.activeWorkers, 1);
    expect(result.starts.length, 1);
    expect(result.finishes.length, 1);
    expect(result.projectedAtRangeEnd, 1);
    expect(result.startingThisWeek, 1);
    expect(result.finishingThisWeek, 1);
  });

  test('overlapping assignments warn but adjacent dates do not', () {
    final result = plan(assignments: [
      assignment('a', 'worker-1', 'site-a',
          start: DateTime(2026, 10, 7), end: DateTime(2026, 10, 10)),
      assignment('b', 'worker-1', 'site-b',
          start: DateTime(2026, 10, 9), end: DateTime(2026, 10, 12)),
      assignment('c', 'worker-1', 'site-b',
          start: DateTime(2026, 10, 13), end: DateTime(2026, 10, 15)),
      assignment('other-worker', 'worker-2', 'site-a',
          start: DateTime(2026, 10, 9), end: DateTime(2026, 10, 12)),
    ]);
    expect(result.conflicts.length, 1);
    expect(result.conflicts.single.overlapStart, DateTime(2026, 10, 9));
    expect(result.conflicts.single.overlapEnd, DateTime(2026, 10, 10));
  });

  test('site and canonical trade filters do not leak other employer data', () {
    final result = plan(siteId: 'site-a', tradeId: 'dryliner', jobs: [
      job('a'),
      job('b', siteId: 'site-b'),
      job('electric', tradeId: 'electrician'),
      job('foreign', owner: 'employer-b'),
    ], assignments: [
      assignment('a', 'worker-1', 'site-a', start: DateTime(2026, 10, 7)),
      assignment('foreign', 'worker-2', 'site-a',
          owner: 'employer-b', start: DateTime(2026, 10, 7)),
    ]);
    expect(result.gapCount, 1);
    expect(result.activeWorkers, 1);
    expect(result.siteSummaries.map((s) => s.siteId), ['site-a']);
    expect(result.tradeSummaries.map((s) => s.tradeId), ['dryliner']);
  });

  test('site filter still shows cross-site assignment conflict', () {
    final result = plan(siteId: 'site-a', assignments: [
      assignment('a', 'worker-1', 'site-a',
          start: DateTime(2026, 10, 7), end: DateTime(2026, 10, 10)),
      assignment('b', 'worker-1', 'site-b',
          start: DateTime(2026, 10, 9), end: DateTime(2026, 10, 11)),
    ]);
    expect(result.assignments.length, 1);
    expect(result.conflicts.length, 1);
  });

  test('planning horizon stays on local calendar midnight across DST', () {
    final range = PlanningWindow.nextDays(DateTime(2026, 10, 24), 4);
    expect(range.end, DateTime(2026, 10, 28));
    expect(range.contains(DateTime(2026, 10, 27, 23)), isTrue);
  });

  test('gap handoff carries canonical trade, safe location, date and vacancy',
      () {
    final result =
        plan(jobs: [job('dryliner-vacancy', positions: 5, filled: 3)]);
    final request = WorkforceTalentRequest.fromGap(result, result.gaps.single);
    expect(request.tradeId, 'dryliner');
    expect(request.location, 'Manchester');
    expect(request.availableBy, planningDay(now));
    expect(request.siteId, 'site-a');
    expect(request.vacancyId, 'dryliner-vacancy');
  });

  test('legacy vacancy trade resolves through the existing taxonomy', () {
    final result = plan(jobs: [job('legacy', tradeId: '')]);
    expect(result.gaps.single.tradeId, 'dryliner');
    expect(
        plan(jobs: [job('legacy', tradeId: '')], tradeId: 'dryliner').gapCount,
        1);
  });
}

Job job(String id,
        {String owner = 'employer-a',
        String siteId = 'site-a',
        String tradeId = 'dryliner',
        int positions = 1,
        int filled = 0,
        String status = 'active',
        String moderation = 'approved'}) =>
    Job(
        id: id,
        title: 'Dryliner',
        trade: 'Dryliner',
        site: 'Site A',
        siteId: siteId,
        canonicalRoleId: tradeId,
        location: 'Manchester',
        street: '',
        city: 'Manchester',
        postcode: '',
        rate: 25,
        lat: 0,
        lng: 0,
        description: '',
        companyName: 'Employer',
        photos: const [],
        jobType: 'hourly',
        duration: '2 weeks',
        employmentType: 'contract',
        ownerId: owner,
        positions: positions,
        filledPositions: filled,
        status: status,
        moderationStatus: moderation);

WorkerAssignment assignment(String id, String workerId, String siteId,
        {required DateTime start,
        DateTime? end,
        String owner = 'employer-a',
        String status = 'active'}) =>
    WorkerAssignment(id, {
      'workerId': workerId,
      'workerDisplayName': 'Worker $workerId',
      'employerContextId': owner,
      'siteId': siteId,
      'siteName': siteId,
      'tradeId': 'dryliner',
      'tradeName': 'Dryliner',
      'status': status,
      'startDate': Timestamp.fromDate(start),
      if (end != null) 'expectedEndDate': Timestamp.fromDate(end),
    });

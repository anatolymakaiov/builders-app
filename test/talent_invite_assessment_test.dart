import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/services/worker_availability_service.dart';
import 'package:test_app/web_app/pages/talent/web_talent_page.dart';
import 'package:test_app/web_app/services/web_talent_service.dart';

void main() {
  final now = DateTime(2026, 10, 8, 12);
  final job = Job.fromFirestore('job-a', {
    'title': 'Dryliner',
    'trade': 'Dryliner',
    'canonicalRoleId': 'dryliner',
    'status': 'active',
    'moderationStatus': 'approved',
  });
  WebTalentCandidate candidate(
          {List<String> trades = const ['dryliner'],
          WorkerAvailability availability = WorkerAvailability.availableNow,
          bool allowsInvites = true,
          DateTime? availableFrom,
          DateTime? confirmedAt}) =>
      WebTalentCandidate(
        id: 'worker-a',
        name: 'Worker A',
        avatarUrl: '',
        tradeIds: trades,
        area: 'Manchester',
        region: 'Greater Manchester',
        experienceYears: 4,
        rating: 4.5,
        ratingCount: 8,
        availability: availability,
        availableFrom: availableFrom,
        confirmedAt: confirmedAt ?? now,
        allowsInvites: allowsInvites,
      );

  test('compatible role is recommended', () {
    expect(assessTalentInvite([candidate()], job, now).recommended, isTrue);
  });

  test('trade/date mismatch warns but does not block alternative own vacancy',
      () {
    final result = assessTalentInvite([
      candidate(
          trades: ['electrician'],
          availability: WorkerAvailability.availableFrom,
          availableFrom: DateTime(2026, 11, 1)),
    ], job, now);
    expect(result.hardBlock, isNull);
    expect(result.warnings, contains('Trade does not match candidate profile'));
    expect(result.warnings,
        contains('Worker may not be available by vacancy start'));
  });

  test('invitation privacy opt-out remains a hard block', () {
    final result = assessTalentInvite([
      candidate(allowsInvites: false),
    ], job, now);
    expect(result.hardBlock, isNotNull);
  });
}

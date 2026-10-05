import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/job_taxonomy_service.dart';
import 'package:test_app/services/worker_availability_service.dart';
import 'package:test_app/web_app/services/web_talent_service.dart';

void main() {
  final now = DateTime(2026, 10, 6);
  WebTalentCandidate candidate(
    String id, {
    List<String> trades = const ['dryliner'],
    String status = 'available_now',
    bool invites = true,
    DateTime? confirmed,
  }) =>
      WebTalentCandidate.fromMap(id, {
        'displayNameShort': 'Anthony M.',
        'tradeIds': trades,
        'generalArea': 'Manchester',
        'region': 'Greater Manchester',
        'availabilityStatus': status,
        'availabilityConfirmedAt':
            Timestamp.fromDate(confirmed ?? DateTime(2026, 10, 5)),
        'availableFrom': Timestamp.fromDate(DateTime.utc(2026, 10, 21)),
        'allowVacancyInvites': invites,
        'email': 'never@example.com',
        'phone': '+447700900123',
        'address': 'Private street',
      });

  test('canonical alias fixer resolves to Dryliner', () {
    expect(JobTaxonomyService.bestRoleFor('fixer')?.id, 'dryliner');
    expect(JobTaxonomyService.bestRoleFor('dry liner')?.id, 'dryliner');
    expect(JobTaxonomyService.bestRoleFor('drywall fixer')?.id, 'dryliner');
  });

  test('single and multiple trade IDs match canonical filters', () {
    final single = candidate('w1');
    final multi = candidate('w2', trades: ['dryliner', 'fire_stopper']);
    expect(single.tradeIds.contains('dryliner'), isTrue);
    expect(multi.tradeIds.contains('dryliner'), isTrue);
    expect(multi.tradeIds.contains('fire_stopper'), isTrue);
    expect(multi.tradeLabel, contains('Dryliner'));
  });

  test('availability, location, invitation and freshness filtering', () {
    const available = WebTalentFilters(
        tradeId: 'dryliner', availability: WorkerAvailability.availableNow);
    expect(candidate('busy', status: 'busy').matches(available, now), isFalse);
    expect(candidate('fresh').matches(available, now), isTrue);
    expect(
        candidate('stale', confirmed: DateTime(2026, 9, 1))
            .matches(available, now),
        isFalse);
    expect(candidate('unknown', status: 'unknown').matches(available, now),
        isFalse);
    expect(candidate('from', status: 'available_from').availabilityLabel(now),
        'Available from 21 Oct 2026');
    expect(
        candidate('noInvites', invites: false).matches(
            const WebTalentFilters(tradeId: 'dryliner', invitesOnly: true),
            now),
        isFalse);
    expect(
        candidate('city').matches(
            const WebTalentFilters(tradeId: 'dryliner', location: 'manchester'),
            now),
        isTrue);
    expect(
        candidate('region').matches(
            const WebTalentFilters(tradeId: 'dryliner', location: 'london'),
            now),
        isFalse);
  });

  test('safe candidate model has no contact or exact address fields', () {
    final item = candidate('w1');
    expect(item.name, 'Anthony M.');
    expect(item.area, 'Manchester');
    expect(item.toString(), isNot(contains('never@example.com')));
    expect(item.toString(), isNot(contains('+447700900123')));
    expect(item.toString(), isNot(contains('Private street')));
  });

  test('pagination merge keeps one candidate per worker ID', () {
    final first = [candidate('a'), candidate('b')];
    final second = [candidate('b'), candidate('c')];
    expect(mergeTalentCandidates(first, second).map((item) => item.id),
        ['a', 'b', 'c']);
  });
}

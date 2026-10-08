import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/services/worker_assignment_service.dart';
import 'package:test_app/web_app/services/site_recruitment_report.dart';
import 'package:test_app/web_app/services/web_sites_service.dart';

void main() {
  Job vacancy(String id, String trade, int positions, int filled,
          {String status = 'active'}) =>
      Job.fromFirestore(id, {
        'title': trade,
        'trade': trade,
        'canonicalRoleId': trade,
        'status': status,
        'moderationStatus': 'approved',
        'positions': positions,
        'filledPositions': filled,
      });

  test('trade report derives demand and workforce without double counting', () {
    final report = siteRecruitmentReport([
      vacancy('job-a', 'dryliner', 10, 6),
      vacancy('job-b', 'dryliner', 2, 0),
      vacancy('closed', 'dryliner', 5, 5, status: 'closed'),
    ], [
      WorkerAssignment('a', {
        'workerId': 'w1',
        'tradeId': 'dryliner',
        'status': 'active',
        'startDate': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'expectedEndDate': Timestamp.fromDate(DateTime(2026, 10, 12)),
      }),
      WorkerAssignment('b', {
        'workerId': 'w2',
        'tradeId': 'dryliner',
        'status': 'scheduled',
        'startDate': Timestamp.fromDate(DateTime(2026, 10, 10)),
      }),
      const WorkerAssignment('cancelled', {
        'workerId': 'w3',
        'tradeId': 'dryliner',
        'status': 'cancelled',
      }),
    ], DateTime(2026, 10, 8));
    expect(report, hasLength(1));
    final row = report.single;
    expect(row.required, 12);
    expect(row.filled, 6);
    expect(row.remaining, 6);
    expect(row.active, 1);
    expect(row.starting, 1);
    expect(row.finishing, 1);
  });

  test('legacy Site match needs a unique exact address and postcode', () {
    const site = WebSite(id: 'site-a', data: {
      'name': 'Manchester Tower',
      'addressLine1': '1 High Street',
      'postcode': 'M1 1AA',
    });
    expect(
        WebSitesService.exactVacancySiteMatch([site],
            name: ' Manchester Tower ',
            addressLine1: '1  High Street',
            postcode: 'm11aa'),
        'site-a');
    expect(
        WebSitesService.exactVacancySiteMatch([site],
            name: 'Manchester Tower',
            addressLine1: '2 High Street',
            postcode: 'M1 1AA'),
        isNull);
    expect(
        WebSitesService.exactVacancySiteMatch([site, site],
            name: 'Manchester Tower',
            addressLine1: '1 High Street',
            postcode: 'M1 1AA'),
        isNull);
    final id = WebSitesService.vacancySiteId(
        'employer-a', 'Manchester Tower', '1 High Street', 'M1 1AA');
    expect(
        id,
        WebSitesService.vacancySiteId(
            'employer-a', ' manchester tower ', '1 HIGH STREET', 'M1 1AA'));
    expect(id, isNot(contains('High Street')));
    expect(id.length, lessThan(80));
  });
}

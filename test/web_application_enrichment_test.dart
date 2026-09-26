import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/services/web_applications_data_service.dart';

void main() {
  test('historical and deleted job references use the application snapshot',
      () {
    for (final status in ['withdrawn', 'rejected', 'offer_rejected', 'closed']) {
      expect(shouldEnrichLiveApplicationJob({'status': status}), isFalse);
    }
    expect(
      shouldEnrichLiveApplicationJob({'status': 'pending', 'jobDeleted': true}),
      isFalse,
    );
    expect(shouldEnrichLiveApplicationJob({'status': 'offer_sent'}), isTrue);

    const summary = WebApplicationSummary(
      id: 'application-1',
      data: {
        'status': 'withdrawn',
        'jobTitle': 'Ceiling Fixer',
        'jobSite': 'Bristol',
        'companyName': 'Example Ltd',
      },
      jobUnavailable: true,
    );
    expect(summary.jobTitle, 'Ceiling Fixer');
    expect(summary.site, 'Bristol');
    expect(summary.companyName, 'Example Ltd');
    expect(summary.jobUnavailable, isTrue);
  });

  test('one enrichment cycle reads each related document once', () async {
    var calls = 0;
    final reads = WebApplicationEnrichmentReads((collection, id) async {
      calls++;
      return {'id': id};
    });
    final results = await Future.wait([
      reads.get('users', 'employer-1'),
      reads.get('users', 'employer-1'),
      reads.get('jobs', 'job-1'),
    ]);
    expect(calls, 2);
    expect(results[0], same(results[1]));
    expect(results[2]?['id'], 'job-1');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/application_job_data_policy.dart';

void main() {
  test('deleted private historical job does not create a live job listener',
      () {
    expect(
      ApplicationJobDataPolicy.shouldListenToLiveJob({
        'jobId': 'deleted-private-job',
        'status': 'withdrawn',
      }),
      isFalse,
    );
    expect(
      ApplicationJobDataPolicy.shouldListenToLiveJob({
        'jobId': 'deleted-private-job',
        'status': 'offer_rejected',
      }),
      isFalse,
    );
  });

  test('historical application renders from its stored job snapshot', () {
    final job = ApplicationJobDataPolicy.fallbackJob('historical-job', {
      'jobTitle': 'Ceiling Fixer',
      'jobTrade': 'Drylining',
      'jobSite': 'Tower Project',
      'siteAddress': '10 Site Road, London',
      'sitePostcode': 'SW1A 1AA',
      'companyName': 'Example Construction',
      'companyLogoUrl': 'https://example.test/logo.jpg',
      'payType': 'daywork',
      'payAmount': '220',
      'duration': 'three weeks',
    });

    expect(job.id, 'historical-job');
    expect(job.displayTitle, 'Ceiling Fixer');
    expect(job.trade, 'Drylining');
    expect(job.site, 'Tower Project');
    expect(job.postcode, 'SW1A 1AA');
    expect(job.companyName, 'Example Construction');
    expect(job.rate, 220);
    expect(job.duration, 'three weeks');
  });

  test('active application continues to use live job data', () {
    for (final status in [
      'pending',
      'negotiation',
      'offer_sent',
      'offer_accepted',
    ]) {
      expect(
        ApplicationJobDataPolicy.shouldListenToLiveJob({'status': status}),
        isTrue,
        reason: status,
      );
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/web_app/services/web_job_filters.dart';

void main() {
  test('legacy vacancy has no siteId and remains visible without site filter',
      () {
    final legacy = Job.fromFirestore('old', {
      'title': 'Dryliner',
      'site': 'Old free-text project',
    });
    expect(legacy.siteId, isEmpty);
    expect(legacy.site, 'Old free-text project');
    expect(matchesSiteFilter(legacy, null), isTrue);
    expect(matchesSiteFilter(legacy, ''), isTrue);
    expect(matchesSiteFilter(legacy, 'new-site'), isFalse);
  });

  test('linked vacancy filters by site ID, not by free-text name', () {
    final linked = Job.fromFirestore('new', {
      'title': 'Electrician',
      'site': 'Site A',
      'siteId': 'site-123',
    });
    expect(matchesSiteFilter(linked, 'site-123'), isTrue);
    expect(matchesSiteFilter(linked, 'site-456'), isFalse);
    expect(linked.copyWith(status: 'closed').siteId, 'site-123');
  });
}

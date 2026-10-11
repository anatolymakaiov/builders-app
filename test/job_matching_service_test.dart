import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/services/job_matching_service.dart';
import 'package:test_app/services/job_taxonomy_service.dart';
import 'package:test_app/web_app/services/web_job_filters.dart';
import 'package:test_app/web_app/pages/jobs/web_worker_vacancy_card.dart';
import 'package:test_app/widgets/smart_job_search.dart';

Job _job(String id, String city, DateTime? start,
        {String trade = 'Dryliner',
        String canonicalRoleId = '',
        int positions = 2,
        int filledPositions = 0,
        String status = 'active'}) =>
    Job(
      id: id,
      title: trade,
      trade: trade,
      canonicalRoleId: canonicalRoleId,
      site: 'Site',
      location: city,
      street: '',
      city: city,
      postcode: '',
      rate: 25,
      lat: 0,
      lng: 0,
      description: '',
      companyName: 'Company',
      photos: const [],
      jobType: 'hourly',
      duration: '2 weeks',
      startDate: start,
      employmentType: '',
      ownerId: 'employer',
      moderationStatus: 'approved',
      status: status,
      positions: positions,
      filledPositions: filledPositions,
    );

void main() {
  final today = DateTime(2026, 10, 10);
  final dryliner = JobTaxonomyService.roleFor('dryliner')!;

  test('Fixer aliases and legacy job resolve to canonical Dryliner', () {
    final legacy = _job('legacy', 'Manchester', today);
    final canonical =
        _job('canonical', 'Manchester', today, canonicalRoleId: 'dryliner');
    for (final alias in [
      'Fixer',
      'Drywall Fixer',
      'Board Fixer',
      'Dry Liner'
    ]) {
      expect(JobTaxonomyService.roleIdFor(alias), 'dryliner');
      final matches = JobMatchingService.rank(
        [legacy, canonical],
        JobMatchCriteria(query: alias, roles: [dryliner]),
      );
      expect(matches.entries.map((entry) => entry.job.id),
          containsAll(['legacy', 'canonical']));
    }
  });

  test('selected locations use OR, outside city is not primary', () {
    final jobs = [
      _job('m', 'Manchester', today),
      _job('l', 'Leeds', today),
      _job('v', 'Liverpool', today),
      _job('b', 'Birmingham', today),
    ];
    final matches = JobMatchingService.rank(
      jobs,
      const JobMatchCriteria(locations: 'Manchester, Leeds; Liverpool'),
    );
    expect(matches.entries.map((entry) => entry.job.id),
        containsAll(['m', 'l', 'v']));
    expect(matches.entries.map((entry) => entry.job.id), isNot(contains('b')));
  });

  test('date ranks near, later, started-open, unknown without excluding', () {
    final matches = JobMatchingService.rank(
      [
        _job('two-weeks', 'Manchester', today.add(const Duration(days: 14))),
        _job('started', 'Manchester', today.subtract(const Duration(days: 7))),
        _job('unknown', 'Manchester', null),
        _job('tomorrow', 'Manchester', today.add(const Duration(days: 1))),
        _job('today', 'Manchester', today),
        _job('week', 'Manchester', today.add(const Duration(days: 7))),
        _job('filled', 'Manchester', today, positions: 1, filledPositions: 1),
        _job('closed', 'Manchester', today, status: 'closed'),
      ],
      JobMatchCriteria(availableFrom: today),
    );
    expect(matches.entries.map((entry) => entry.job.id),
        ['today', 'tomorrow', 'week', 'two-weeks', 'started', 'unknown']);
    expect(matches.entries[0].category, JobMatchCategory.bestMatch);
    expect(matches.entries[2].category, JobMatchCategory.startsLater);
    expect(matches.entries[4].category,
        JobMatchCategory.alreadyStartedStillHiring);
    expect(matches.entries[5].category, JobMatchCategory.dateUnknown);
  });

  test('zero best shows alternatives; true zero remains empty', () {
    final jobs = [
      _job('elsewhere', 'Birmingham', today.add(const Duration(days: 14)))
    ];
    final similar = JobMatchingService.rank(
      jobs,
      JobMatchCriteria(
          query: 'Fixer', locations: 'Manchester', availableFrom: today),
    );
    expect(similar.hasSimilarButNoBest, isTrue);
    expect(
        similar.entries.single.category, JobMatchCategory.alternativeLocation);
    final none = JobMatchingService.rank(
      jobs,
      JobMatchCriteria(
          query: 'Electrician', locations: 'Manchester', availableFrom: today),
    );
    expect(none.isEmpty, isTrue);
  });

  test('public matching excludes closed/filled; owner filter can retain closed',
      () {
    final closed = _job('closed', 'Manchester', today, status: 'closed');
    final filled =
        _job('filled', 'Manchester', today, positions: 1, filledPositions: 1);
    expect(
        JobMatchingService.rank([closed, filled], const JobMatchCriteria())
            .entries,
        isEmpty);
    expect(
        const WebJobFilters()
            .apply([closed], '', requirePublic: false)
            .single
            .id,
        'closed');
  });

  test('stable category ordering and bounded alternative group', () {
    final jobs = List.generate(
        40,
        (index) =>
            _job('job-$index', 'Leeds', today.add(const Duration(days: 7))));
    final first = JobMatchingService.rank(
        jobs, const JobMatchCriteria(locations: 'Manchester'));
    final again = JobMatchingService.rank(jobs.reversed.toList(),
        const JobMatchCriteria(locations: 'Manchester'));
    expect(first.entries.length, JobMatchingService.maxAlternativeLocations);
    expect(first.entries.map((entry) => entry.job.id),
        again.entries.map((entry) => entry.job.id));
  });

  test('Web, Mobile and AI-equivalent criteria share matching results', () {
    final jobs = [
      _job('one', 'Manchester', today),
      _job('two', 'Leeds', today.add(const Duration(days: 14))),
    ];
    final criteria = JobMatchCriteria(
      roles: [dryliner],
      query: 'Fixer',
      locations: 'Manchester, Leeds',
      availableFrom: today,
    );
    final ranked = JobMatchingService.rank(jobs, criteria);
    final web = WebJobFilters(
      roles: [dryliner],
      city: 'Manchester, Leeds',
      availableFrom: today,
    ).apply(jobs, 'Fixer');
    final mobile = jobs
        .where((job) => jobMatchesSearch(
              job,
              roles: [dryliner],
              query: 'Fixer',
              filters: JobSearchFilters(
                  city: 'Manchester, Leeds', availableFrom: today),
              originJobs: jobs,
            ))
        .toList();
    expect(
        web.map((job) => job.id), ranked.entries.map((entry) => entry.job.id));
    expect(mobile.map((job) => job.id).toSet(),
        ranked.entries.map((entry) => entry.job.id).toSet());
  });

  testWidgets('Web vacancy card shows the shared match reason',
      (tester) async {
    final job = _job('one', 'Manchester', today);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: WebWorkerVacancyCard(
            job: job,
            selected: false,
            saved: false,
            onTap: () {},
            matchLabel: 'Best match',
          ),
        ),
      ),
    ));
    expect(find.text('Best match'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

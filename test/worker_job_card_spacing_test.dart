import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/widgets/job_card.dart';

void main() {
  final job = Job(
    id: 'job-1',
    title: 'Experienced ceiling fixer for a long commercial project',
    trade: 'Ceiling Fixer',
    site: 'Manchester',
    location: 'Manchester',
    street: '',
    city: 'Manchester',
    postcode: 'M1 1AE',
    rate: 25,
    lat: 0,
    lng: 0,
    description: 'Vacancy description',
    companyName: 'Construction Company',
    photos: const [],
    jobType: 'hourly',
    duration: '5 months',
    startDate: DateTime(2026, 10, 12),
    employmentType: '',
    ownerId: 'unknown',
    postedAt: DateTime(2026, 9, 28),
  );

  for (final width in [390.0, 360.0]) {
    testWidgets('Worker card is compact without clipping at ${width.toInt()}px',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var opened = false;
      Future<double> cardHeight(bool compact, {bool applied = false}) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: JobCard(
                key: const ValueKey('job-card'),
                job: job,
                compactWorkerLayout: compact,
                workerApplied: compact ? applied : null,
                onTap: () => opened = true,
                trailingAction: IconButton(
                  tooltip: 'Save job',
                  icon: const Icon(Icons.favorite_border),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Posted: 28 Sep 2026'), findsOneWidget);
        expect(find.text('5 months'), findsOneWidget);
        expect(find.text('Start: 12 Oct 2026'), findsOneWidget);
        if (compact) {
          expect(
              find.text(applied ? 'Applied' : 'Not Applied'), findsOneWidget);
          expect(
            tester
                .getTopLeft(find.text(applied ? 'Applied' : 'Not Applied'))
                .dy,
            greaterThan(tester.getTopLeft(find.byIcon(Icons.business)).dy),
          );
        }
        return tester.getSize(find.byKey(const ValueKey('job-card'))).height;
      }

      final normalHeight = await cardHeight(false);
      final compactHeight = await cardHeight(true);
      expect(compactHeight, lessThan(normalHeight));
      await cardHeight(true, applied: true);

      await tester.tap(find.byKey(const ValueKey('job-card')));
      expect(opened, isTrue);
    });
  }
}

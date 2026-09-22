import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/worker_review.dart';
import 'package:test_app/widgets/worker_rating_reviews.dart';

WorkerReview review({
  required String id,
  required double rating,
  required DateTime date,
}) {
  return WorkerReview(
    id: id,
    reviewerName: 'Build Co $id',
    reviewerLogoUrl: '',
    rating: rating,
    text: 'Review $id',
    createdAt: date,
    jobTitle: 'Site role',
    jobId: 'job-$id',
    applicationId: 'application-$id',
  );
}

void main() {
  final reviews = [
    review(id: 'older', rating: 4, date: DateTime(2026, 1, 1)),
    review(id: 'newer', rating: 5, date: DateTime(2026, 2, 1)),
  ];

  test('average and review count use published review data', () {
    expect(workerAverageRating(reviews), 4.5);
    expect(reviews.length, 2);
    expect(workerAverageRating(const []), 0);
  });

  test('legacy review without rating remains visible without skewing average',
      () {
    final legacy = WorkerReview.fromMap('legacy', {
      'employerName': 'Legacy employer',
      'review': 'Legacy feedback',
    });
    final combined = [...reviews, legacy];

    expect(legacy.rating, 0);
    expect(combined.length, 3);
    expect(workerAverageRating(combined), 4.5);
  });

  test('star representation supports half ratings', () {
    expect(
      workerRatingStars(4.5),
      [
        RatingStarFill.full,
        RatingStarFill.full,
        RatingStarFill.full,
        RatingStarFill.full,
        RatingStarFill.half,
      ],
    );
  });

  test('reviews sort by rating and date', () {
    expect(
      sortWorkerReviews(reviews, WorkerReviewSort.highest).first.id,
      'newer',
    );
    expect(
      sortWorkerReviews(reviews, WorkerReviewSort.lowest).first.id,
      'older',
    );
    expect(
      sortWorkerReviews(reviews, WorkerReviewSort.newest).first.id,
      'newer',
    );
    expect(
      sortWorkerReviews(reviews, WorkerReviewSort.oldest).first.id,
      'older',
    );
  });

  testWidgets('summary renders numeric rating, stars, and count',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkerRatingSummary(
            reviews: reviews,
            onViewReviews: () {},
          ),
        ),
      ),
    );

    expect(find.text('4.5 / 5'), findsOneWidget);
    expect(find.text('2 reviews'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(4));
    expect(find.byIcon(Icons.star_half), findsOneWidget);
  });

  testWidgets('summary uses singular label for one review', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkerRatingSummary(
            reviews: const [
              WorkerReview(
                id: 'one',
                reviewerName: 'One reviewer',
                reviewerLogoUrl: '',
                rating: 5,
                text: 'Excellent',
                createdAt: null,
                jobTitle: '',
                jobId: '',
                applicationId: '',
              ),
            ],
            onViewReviews: () {},
          ),
        ),
      ),
    );

    expect(find.text('1 review'), findsOneWidget);
  });

  testWidgets('empty viewer shows an empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WorkerReviewsViewer(reviews: [])),
      ),
    );

    expect(find.text('No reviews yet'), findsOneWidget);
    expect(find.text('0.0 / 5'), findsOneWidget);
  });

  testWidgets('review modal opens and closes without leaving the profile',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showWorkerReviewsViewer(context, reviews),
              child: const Text('View reviews'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('View reviews'));
    await tester.pumpAndSettle();
    expect(find.text('Worker reviews'), findsOneWidget);

    await tester.tap(find.byTooltip('Close reviews'));
    await tester.pumpAndSettle();
    expect(find.text('Worker reviews'), findsNothing);
    expect(find.text('View reviews'), findsOneWidget);
  });
}

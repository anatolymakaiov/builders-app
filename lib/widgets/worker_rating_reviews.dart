import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/worker_review.dart';
import 'app_cached_image.dart';

class WorkerRatingStars extends StatelessWidget {
  const WorkerRatingStars({
    super.key,
    required this.rating,
    this.size = 20,
  });

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${rating.toStringAsFixed(1)} out of 5 stars',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final star in workerRatingStars(rating))
            Icon(
              switch (star) {
                RatingStarFill.full => Icons.star,
                RatingStarFill.half => Icons.star_half,
                RatingStarFill.empty => Icons.star_border,
              },
              size: size,
              color: const Color(0xFFF4A825),
            ),
        ],
      ),
    );
  }
}

class WorkerRatingSummary extends StatelessWidget {
  const WorkerRatingSummary({
    super.key,
    required this.reviews,
    required this.onViewReviews,
  });

  final List<WorkerReview> reviews;
  final VoidCallback onViewReviews;

  @override
  Widget build(BuildContext context) {
    final average = workerAverageRating(reviews);
    final count = reviews.length;
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        WorkerRatingStars(rating: average),
        Text(
          '${average.toStringAsFixed(1)} / 5',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        Text('$count ${count == 1 ? 'review' : 'reviews'}'),
        TextButton.icon(
          onPressed: onViewReviews,
          icon: const Icon(Icons.rate_review_outlined),
          label: const Text('View reviews'),
        ),
      ],
    );
  }
}

Future<void> showWorkerReviewsViewer(
  BuildContext context,
  List<WorkerReview> reviews,
) {
  if (kIsWeb) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
          child: WorkerReviewsViewer(reviews: reviews),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: .86,
      child: WorkerReviewsViewer(reviews: reviews),
    ),
  );
}

class WorkerReviewsViewer extends StatefulWidget {
  const WorkerReviewsViewer({super.key, required this.reviews});

  final List<WorkerReview> reviews;

  @override
  State<WorkerReviewsViewer> createState() => _WorkerReviewsViewerState();
}

class _WorkerReviewsViewerState extends State<WorkerReviewsViewer> {
  WorkerReviewSort sort = WorkerReviewSort.newest;

  @override
  Widget build(BuildContext context) {
    final reviews = sortWorkerReviews(widget.reviews, sort);
    final average = workerAverageRating(widget.reviews);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Worker reviews',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close reviews',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              WorkerRatingStars(rating: average),
              Text('${average.toStringAsFixed(1)} / 5'),
              Text(
                '${widget.reviews.length} '
                '${widget.reviews.length == 1 ? 'review' : 'reviews'}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: DropdownButton<WorkerReviewSort>(
              value: sort,
              onChanged: (value) {
                if (value != null) setState(() => sort = value);
              },
              items: const [
                DropdownMenuItem(
                  value: WorkerReviewSort.newest,
                  child: Text('Newest first'),
                ),
                DropdownMenuItem(
                  value: WorkerReviewSort.oldest,
                  child: Text('Oldest first'),
                ),
                DropdownMenuItem(
                  value: WorkerReviewSort.highest,
                  child: Text('Highest rating first'),
                ),
                DropdownMenuItem(
                  value: WorkerReviewSort.lowest,
                  child: Text('Lowest rating first'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: reviews.isEmpty
                ? const Center(child: Text('No reviews yet'))
                : ListView.separated(
                    itemCount: reviews.length,
                    separatorBuilder: (_, __) => const Divider(height: 24),
                    itemBuilder: (context, index) =>
                        _WorkerReviewTile(review: reviews[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _WorkerReviewTile extends StatelessWidget {
  const _WorkerReviewTile({required this.review});

  final WorkerReview review;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCachedCircleAvatar(
          imageUrl: review.reviewerLogoUrl,
          fallbackIcon: Icons.business_outlined,
          radius: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      review.reviewerName.isEmpty
                          ? 'Employer'
                          : review.reviewerName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  WorkerRatingStars(rating: review.rating, size: 16),
                  const SizedBox(width: 6),
                  Text(review.rating.toStringAsFixed(1)),
                ],
              ),
              if (review.createdAt != null) ...[
                const SizedBox(height: 3),
                Text(
                  _formatReviewDate(review.createdAt!),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (review.jobTitle.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  review.jobTitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (review.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(review.text),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _formatReviewDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

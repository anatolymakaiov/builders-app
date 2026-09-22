import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/worker_review.dart';
import '../../../widgets/worker_rating_reviews.dart';
import '../../../widgets/worker_review_workflow.dart';

class WebWorkerReviews extends StatefulWidget {
  const WebWorkerReviews({
    super.key,
    required this.workerId,
    required this.ownProfile,
  });

  final String workerId;
  final bool ownProfile;

  @override
  State<WebWorkerReviews> createState() => _WebWorkerReviewsState();
}

class _WebWorkerReviewsState extends State<WebWorkerReviews> {
  late Future<QuerySnapshot<Map<String, dynamic>>> future = load();

  Future<QuerySnapshot<Map<String, dynamic>>> load() =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.workerId)
          .collection('reviews')
          .get();

  @override
  void didUpdateWidget(covariant WebWorkerReviews oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workerId != widget.workerId) future = load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Employer reviews',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (widget.ownProfile) ...[
          const SizedBox(height: 8),
          WorkerReviewRequestsPanel(
            onChanged: () => setState(() => future = load()),
          ),
        ],
        const SizedBox(height: 8),
        FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton(
                onPressed: () => setState(() => future = load()),
                child: const Text('Could not load reviews. Retry'),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final reviews = snapshot.data!.docs
                .map((doc) => WorkerReview.fromMap(doc.id, doc.data()))
                .toList(growable: false);
            return WorkerRatingSummary(
              reviews: reviews,
              onViewReviews: () => showWorkerReviewsViewer(context, reviews),
            );
          },
        ),
      ],
    );
  }
}

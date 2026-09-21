import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../widgets/app_cached_image.dart';
import '../../../widgets/worker_review_workflow.dart';

class WebWorkerReviews extends StatefulWidget {
  const WebWorkerReviews(
      {super.key, required this.workerId, required this.ownProfile});
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
          .orderBy('createdAt', descending: true)
          .get();
  @override
  void didUpdateWidget(covariant WebWorkerReviews oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workerId != widget.workerId) future = load();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('Employer reviews',
                  style: Theme.of(context).textTheme.titleLarge)),
        ]),
        if (widget.ownProfile) ...[
          const SizedBox(height: 8),
          WorkerReviewRequestsPanel(
            onChanged: () => setState(() => future = load()),
          ),
        ],
        FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return TextButton(
                    onPressed: () => setState(() => future = load()),
                    child: const Text('Could not load reviews. Retry'));
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) return const Text('No reviews yet');
              final average = docs.fold<double>(
                      0,
                      (total, doc) =>
                          total +
                          ((doc.data()['rating'] as num?)?.toDouble() ?? 0)) /
                  docs.length;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${average.toStringAsFixed(1)} / 5 (${docs.length} reviews)'),
                    for (final doc in docs)
                      ListTile(
                          leading: AppCachedCircleAvatar(
                            imageUrl: doc.data()['employerLogoUrl']?.toString(),
                            fallbackIcon: Icons.business_outlined,
                            radius: 20,
                          ),
                          title: Text(
                              '${doc.data()['employerName'] ?? 'Employer'} - ${doc.data()['rating'] ?? ''}/5'),
                          subtitle: Text([
                            if ((doc.data()['jobTitle']?.toString().trim() ??
                                    '')
                                .isNotEmpty)
                              doc.data()['jobTitle'].toString().trim(),
                            doc.data()['review']?.toString() ?? '',
                          ].where((value) => value.isNotEmpty).join('\n'))),
                  ]);
            }),
      ]);
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/web_profile_communication.dart';

class WebWorkerReviews extends StatefulWidget {
  const WebWorkerReviews(
      {super.key, required this.workerId, required this.canReview});
  final String workerId;
  final bool canReview;
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
          if (widget.canReview)
            TextButton.icon(
                onPressed: () async {
                  final saved = await showDialog<bool>(
                      context: context,
                      builder: (_) => _ReviewDialog(workerId: widget.workerId));
                  if (mounted && saved == true) setState(() => future = load());
                },
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Add review'))
        ]),
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
                          title: Text(
                              '${doc.data()['employerName'] ?? 'Employer'} - ${doc.data()['rating'] ?? ''}/5'),
                          subtitle:
                              Text(doc.data()['review']?.toString() ?? '')),
                  ]);
            }),
      ]);
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.workerId});
  final String workerId;
  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final text = TextEditingController();
  int rating = 5;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Leave review'),
          content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                        5,
                        (index) => IconButton(
                            onPressed: busy
                                ? null
                                : () => setState(() => rating = index + 1),
                            tooltip: '${index + 1} stars',
                            icon: Icon(index < rating
                                ? Icons.star
                                : Icons.star_border)))),
                TextField(
                    controller: text,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Review')),
                if (error != null) Text(error!),
              ])),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: busy ? null : submit, child: const Text('Submit'))
          ]);
  Future<void> submit() async {
    setState(() => busy = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final db = FirebaseFirestore.instance;
      final employer = (await db.collection('users').doc(uid).get()).data();
      final worker =
          (await db.collection('users').doc(widget.workerId).get()).data();
      if (uid == widget.workerId ||
          employer?['role'] != 'employer' ||
          WebProfileCommunication.unavailable(employer) ||
          WebProfileCommunication.unavailable(worker)) {
        throw StateError('Review is not available.');
      }
      await db
          .collection('users')
          .doc(widget.workerId)
          .collection('reviews')
          .add({
        'employerId': uid,
        'employerName':
            employer!['companyName'] ?? employer['name'] ?? 'Employer',
        'rating': rating,
        'review': text.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Aggregate display is derived from reviews; cross-user profile writes are protected.
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

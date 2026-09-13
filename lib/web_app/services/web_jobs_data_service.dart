import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/job.dart';

class WebJobsDataService {
  WebJobsDataService({
    FirebaseFirestore? firestore,
    this.pollInterval = const Duration(seconds: 8),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration pollInterval;

  Stream<List<Job>> jobs({
    required String userId,
    required String role,
  }) {
    Timer? timer;
    var lastValue = const <Job>[];
    var loading = false;
    final controller = StreamController<List<Job>>();

    Future<void> refresh() async {
      if (loading || controller.isClosed) return;
      loading = true;
      try {
        lastValue = await loadJobs(userId: userId, role: role);
        if (!controller.isClosed) controller.add(lastValue);
      } catch (_) {
        if (!controller.isClosed) controller.add(lastValue);
      } finally {
        loading = false;
      }
    }

    controller.onListen = () {
      unawaited(refresh());
      timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
    };
    controller.onCancel = () {
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<List<Job>> loadJobs({
    required String userId,
    required String role,
  }) async {
    final snapshot = await _firestore.collection('jobs').get();
    final jobs = snapshot.docs
        .map((doc) => Job.fromFirestore(doc.id, doc.data()))
        .where((job) {
      if (role == 'employer' && job.ownerId == userId) return !job.deleted;
      return job.isPubliclyVisible;
    }).toList();

    jobs.sort((a, b) {
      final aDate = a.postedAt ?? a.createdAt;
      final bDate = b.postedAt ?? b.createdAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return jobs;
  }
}

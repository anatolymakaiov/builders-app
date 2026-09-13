import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/job.dart';
import 'web_data_state.dart';

class WebJobsDataService {
  WebJobsDataService({
    FirebaseFirestore? firestore,
    this.pollInterval = const Duration(seconds: 8),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration pollInterval;

  Stream<WebDataState<List<Job>>> jobs({
    required String userId,
    required String role,
  }) {
    Timer? timer;
    var lastValue = const <Job>[];
    var loading = false;
    final controller = StreamController<WebDataState<List<Job>>>();

    Future<void> refresh() async {
      if (loading || controller.isClosed) return;
      loading = true;
      try {
        lastValue = await loadJobs(userId: userId, role: role);
        if (!controller.isClosed) {
          controller.add(WebDataState.data(lastValue));
        }
      } catch (error) {
        // Keep the previous rendered list if a poll fails, but surface the
        // backend error so the UI does not mislabel failures as empty results.
        debugPrint('WEB JOBS LOAD ERROR $error');
        if (!controller.isClosed) {
          controller.add(WebDataState.error(error, lastData: lastValue));
        }
      } finally {
        loading = false;
      }
    }

    controller.onListen = () {
      controller.add(const WebDataState.loading());
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
    final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final publicSnapshot = await _firestore
        .collection('jobs')
        .where('moderationStatus', isEqualTo: 'approved')
        .where('status', whereIn: ['active', 'published', 'open']).get();
    for (final doc in publicSnapshot.docs) {
      docsById[doc.id] = doc;
    }

    if (role == 'employer') {
      for (final field in const [
        'ownerId',
        'employerId',
        'createdBy',
        'userId',
      ]) {
        final ownerSnapshot = await _firestore
            .collection('jobs')
            .where(field, isEqualTo: userId)
            .get();
        for (final doc in ownerSnapshot.docs) {
          docsById[doc.id] = doc;
        }
      }
    }

    final jobs = docsById.values.map((doc) {
      return Job.fromFirestore(doc.id, doc.data());
    }).where((job) {
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

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

  Stream<WebDataState<WebJobsResult>> jobs({
    required String userId,
    required String role,
  }) {
    Timer? timer;
    var lastValue = const WebJobsResult(
      publicJobs: <Job>[],
      ownerJobs: <Job>[],
    );
    var loading = false;
    final controller = StreamController<WebDataState<WebJobsResult>>();

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

  Future<WebJobsResult> loadJobs({
    required String userId,
    required String role,
  }) async {
    final publicDocsById =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final publicSnapshot = await _firestore
        .collection('jobs')
        .where('moderationStatus', isEqualTo: 'approved')
        .where('status', whereIn: ['active', 'published', 'open']).get();
    for (final doc in publicSnapshot.docs) {
      publicDocsById[doc.id] = doc;
    }

    final publicJobs = publicDocsById.values
        .map((doc) => Job.fromFirestore(doc.id, doc.data()))
        .where(_isPublicWebJob)
        .toList();
    _sortNewest(publicJobs);

    final ownerDocsById =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
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
          ownerDocsById[doc.id] = doc;
        }
      }
    }

    final ownerJobs = ownerDocsById.values
        .map((doc) => Job.fromFirestore(doc.id, doc.data()))
        .where((job) => _isOwnerWebJob(job, userId))
        .toList();
    _sortNewest(ownerJobs);

    return WebJobsResult(publicJobs: publicJobs, ownerJobs: ownerJobs);
  }

  bool _isPublicWebJob(Job job) {
    final status = job.status.trim().toLowerCase();
    return job.isPubliclyVisible &&
        !job.isClosed &&
        status != 'pending' &&
        status != 'pending_review' &&
        status != 'rejected' &&
        status != 'draft' &&
        status != 'on_hold' &&
        status != 'suspended' &&
        status != 'expired';
  }

  bool _isOwnerWebJob(Job job, String userId) {
    if (job.ownerId != userId) return false;
    return !job.deleted &&
        !job.employerDeleted &&
        !job.companyDeleted &&
        job.status.trim().toLowerCase() != 'deleted';
  }

  void _sortNewest(List<Job> jobs) {
    jobs.sort((a, b) {
      final aDate = a.postedAt ?? a.createdAt;
      final bDate = b.postedAt ?? b.createdAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
  }

  Future<Set<String>> savedJobIds(String userId) async {
    final snapshot = await _firestore
        .collection('saved_jobs')
        .doc(userId)
        .collection('jobs')
        .get();
    return snapshot.docs.map((doc) => doc.id).toSet();
  }

  Future<void> toggleSavedJob({
    required String userId,
    required String jobId,
    required bool isSaved,
  }) async {
    final ref = _firestore
        .collection('saved_jobs')
        .doc(userId)
        .collection('jobs')
        .doc(jobId);
    if (isSaved) {
      await ref.delete();
    } else {
      await ref.set({'savedAt': FieldValue.serverTimestamp()});
    }
  }

  Future<bool> hasSingleApplication({
    required String userId,
    required String jobId,
  }) async {
    final snapshot = await _firestore
        .collection('applications')
        .where('jobId', isEqualTo: jobId)
        .where('workerId', isEqualTo: userId)
        .get();
    return snapshot.docs.any((doc) {
      final data = doc.data();
      final type = data['type']?.toString();
      final status = data['status']?.toString().toLowerCase().trim();
      return type != 'team' && status != 'withdrawn' && status != 'deleted';
    });
  }

  Future<void> applyAsSingle({
    required String userId,
    required Job job,
  }) async {
    if (await hasSingleApplication(userId: userId, jobId: job.id)) {
      throw StateError('already_applied');
    }
    final jobRef = _firestore.collection('jobs').doc(job.id);
    final applicationRef = _firestore.collection('applications').doc();
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final workerName =
        (userDoc.data()?['name'] ?? userDoc.data()?['displayName'] ?? 'Worker')
            .toString();

    await _firestore.runTransaction((transaction) async {
      final jobSnap = await transaction.get(jobRef);
      if (!jobSnap.exists) throw StateError('job_not_found');
      final jobData = jobSnap.data() ?? <String, dynamic>{};
      final currentJob = Job.fromFirestore(job.id, jobData);
      if (!_isPublicWebJob(currentJob)) throw StateError('job_not_available');
      if (currentJob.remainingPositions <= 0) {
        throw StateError('no_positions_left');
      }
      final ownerId = currentJob.ownerId;
      if (ownerId.isEmpty || ownerId == 'unknown') {
        throw StateError('missing_employer');
      }

      transaction.set(applicationRef, {
        'jobId': job.id,
        'jobTitle': currentJob.displayTitle,
        'jobTrade': currentJob.trade,
        'jobSite': currentJob.site,
        ..._applicationAddressFields(currentJob, jobData),
        ..._applicationSnapshotFields(currentJob, jobData),
        'workerId': userId,
        'applicantId': userId,
        'workerName': workerName,
        'type': 'single',
        'members': [userId],
        'workersCount': 1,
        'membersStatus': {userId: 'pending'},
        'employerId': ownerId,
        'ownerId': ownerId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'applicationActivityAt': FieldValue.serverTimestamp(),
        'unreadFor': [ownerId],
      });
    });
  }

  Map<String, dynamic> _applicationSnapshotFields(
    Job job,
    Map<String, dynamic> data,
  ) {
    return {
      'jobType': (data['jobType'] ?? job.jobType).toString(),
      'rate': data['rate'] ?? job.rate,
      'jobRate': data['rate'] ?? job.rate,
      'duration': (data['duration'] ?? job.duration).toString(),
      'jobDuration': (data['duration'] ?? job.duration).toString(),
      'companyName': job.companyName,
      if ((job.companyLogo ?? '').trim().isNotEmpty)
        'companyLogoUrl': job.companyLogo,
    };
  }

  Map<String, dynamic> _applicationAddressFields(
    Job job,
    Map<String, dynamic> data,
  ) {
    final street = (data['siteStreet'] ?? job.street).toString().trim();
    final city = (data['siteCity'] ?? job.city).toString().trim();
    final postcode = (data['sitePostcode'] ?? job.postcode).toString().trim();
    final county = (data['siteCounty'] ?? job.county).toString().trim();
    final composed = [street, city, postcode]
        .where((part) => part.trim().isNotEmpty)
        .join(', ');
    final fullAddress = (data['siteAddress'] ??
            data['fullAddress'] ??
            data['location'] ??
            job.fullAddress)
        .toString()
        .trim();
    return {
      'siteStreet': street,
      'siteCity': city,
      'sitePostcode': postcode,
      'siteCounty': county,
      'siteAddress': fullAddress.isNotEmpty ? fullAddress : composed,
      'fullAddress': fullAddress.isNotEmpty ? fullAddress : composed,
    };
  }
}

class WebJobsResult {
  const WebJobsResult({
    required this.publicJobs,
    required this.ownerJobs,
  });

  final List<Job> publicJobs;
  final List<Job> ownerJobs;

  List<Job> jobsForMode(WebJobsMode mode, String role) {
    if (role == 'employer' && mode == WebJobsMode.owner) return ownerJobs;
    return publicJobs;
  }
}

enum WebJobsMode { owner, market }

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/job.dart';
import 'application_activity_service.dart';
import 'notification_service.dart';

enum ApplicationStatus {
  pending,
  accepted,
  rejected,
}

class JobRepository {
  final _db = FirebaseFirestore.instance;
  final notificationService = NotificationService();

  bool _isDeletedOrInactiveJobData(
    Map<String, dynamic> data, {
    bool excludeNonPublicStatuses = false,
  }) {
    final status = data["status"]?.toString().trim().toLowerCase() ?? "";
    return data["deleted"] == true ||
        data["isDeleted"] == true ||
        data["active"] == false ||
        data["isActive"] == false ||
        data["employerDeleted"] == true ||
        data["companyDeleted"] == true ||
        data["deletionReason"] != null ||
        status == "deleted" ||
        status == "inactive" ||
        status == "hidden" ||
        status == "archived" ||
        status == "suspended" ||
        status == "expired" ||
        (excludeNonPublicStatuses &&
            (status == "rejected" ||
                status == "on_hold" ||
                status == "pending_review" ||
                status == "moderation_required"));
  }

  bool _isHardDeletedJobData(Map<String, dynamic> data) {
    final status = data["status"]?.toString().trim().toLowerCase() ?? "";
    return data["deleted"] == true ||
        data["isDeleted"] == true ||
        data["employerDeleted"] == true ||
        data["companyDeleted"] == true ||
        data["deletionReason"] != null ||
        status == "deleted";
  }

  Future<bool> _isOwnerActive(String ownerId) async {
    if (ownerId.trim().isEmpty || ownerId == "unknown") return false;

    final ownerDoc = await _db.collection("users").doc(ownerId).get();
    if (!ownerDoc.exists) return false;

    final data = ownerDoc.data() ?? <String, dynamic>{};
    final status = data["status"]?.toString().trim().toLowerCase() ?? "";
    return data["deleted"] != true &&
        data["accountDeleted"] != true &&
        data["anonymised"] != true &&
        data["active"] != false &&
        status != "deleted";
  }

  Future<List<Job>> _filterJobsWithActiveOwners(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required bool requirePublicVisibility,
  }) async {
    final activeOwnerCache = <String, bool>{};
    var filteredDeletedJobsCount = 0;
    final jobs = <Job>[];

    for (final doc in docs) {
      final data = doc.data();
      if (_isDeletedOrInactiveJobData(
        data,
        excludeNonPublicStatuses: requirePublicVisibility,
      )) {
        filteredDeletedJobsCount += 1;
        continue;
      }

      final ownerId = (data["ownerId"] ??
              data["employerId"] ??
              data["createdBy"] ??
              data["userId"] ??
              "")
          .toString();

      var active = activeOwnerCache[ownerId];
      if (active == null) {
        active = await _isOwnerActive(ownerId);
        activeOwnerCache[ownerId] = active;
      }
      if (!active) {
        filteredDeletedJobsCount += 1;
        continue;
      }

      final job = Job.fromFirestore(doc.id, data);
      if (requirePublicVisibility && !job.isPubliclyVisible) {
        filteredDeletedJobsCount += 1;
        continue;
      }
      jobs.add(job);
    }

    debugPrint(
      "visibleJobsCount=${jobs.length} filteredDeletedJobsCount=$filteredDeletedJobsCount",
    );

    jobs.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return jobs;
  }

  /// 🔹 ВСЕ JOBS
  Stream<List<Job>> getJobs() {
    return _db
        .collection('jobs')
        .where('moderationStatus', isEqualTo: 'approved')
        .where('status', whereIn: ['active', 'published', 'open'])
        .snapshots(includeMetadataChanges: true)
        .asyncMap(
          (snapshot) => _filterJobsWithActiveOwners(
            snapshot.docs,
            requirePublicVisibility: true,
          ),
        );
  }

  /// 🔥 JOBS ПО РАБОТОДАТЕЛЮ (НОВОЕ)
  Stream<List<Job>> getJobsByOwner(String ownerId) {
    final controller = StreamController<List<Job>>();
    final latestByField =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emitJobs() {
      final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final docs in latestByField.values) {
        for (final doc in docs) {
          docsById[doc.id] = doc;
        }
      }

      final jobs = docsById.values.where((doc) {
        final data = doc.data();
        return !_isHardDeletedJobData(data);
      }).map((doc) {
        final data = doc.data();
        return Job.fromFirestore(doc.id, data);
      }).toList();

      debugPrint(
        "MY JOBS LOAD START employerId=$ownerId companyId=$ownerId jobsCount=${jobs.length}",
      );
      if (jobs.isEmpty) {
        debugPrint("MY JOBS EMPTY STATE");
      }

      jobs.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      if (!controller.isClosed) {
        controller.add(jobs);
      }
    }

    controller.onListen = () {
      for (final field in const [
        "ownerId",
        "employerId",
        "createdBy",
        "userId"
      ]) {
        final subscription = _db
            .collection('jobs')
            .where(field, isEqualTo: ownerId)
            .snapshots(includeMetadataChanges: true)
            .listen(
          (snapshot) {
            latestByField[field] = snapshot.docs;
            emitJobs();
          },
          onError: controller.addError,
        );
        subscriptions.add(subscription);
      }
    };

    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };

    return controller.stream;
  }

  /// 🔥 ПРОВЕРКА: УЖЕ ОТКЛИКНУЛСЯ?
  Future<bool> hasApplied(String jobId, String userId) async {
    final snapshot = await _db
        .collection('applications')
        .where('jobId', isEqualTo: jobId)
        .where('workerId', isEqualTo: userId)
        .get();

    return snapshot.docs.any((doc) {
      final data = doc.data();
      final type = data["type"]?.toString();
      final status = data["status"]?.toString();
      return type != "team" && status != "withdrawn";
    });
  }

  /// 🔥 APPLY
  Future<void> applyToJob(String jobId, String userId) async {
    /// 1. защита от дублей
    final alreadyApplied = await hasApplied(jobId, userId);
    if (alreadyApplied) return;

    /// 2. получаем job
    final jobDoc = await _db.collection('jobs').doc(jobId).get();

    if (!jobDoc.exists) {
      throw Exception("Job not found");
    }

    final jobData = jobDoc.data()!;
    final employerId = jobData["ownerId"];

    if (employerId == null) {
      throw Exception("Job has no ownerId");
    }

    final userDoc = await _db.collection('users').doc(userId).get();
    final workerName =
        (userDoc.data()?["name"] ?? userDoc.data()?["displayName"] ?? "Worker")
            .toString();
    final siteStreet =
        (jobData["siteStreet"] ?? jobData["street"] ?? "").toString().trim();
    final siteCity =
        (jobData["siteCity"] ?? jobData["city"] ?? "").toString().trim();
    final sitePostcode = (jobData["sitePostcode"] ?? jobData["postcode"] ?? "")
        .toString()
        .trim();
    final siteCounty =
        (jobData["siteCounty"] ?? jobData["county"] ?? "").toString().trim();
    final siteAddress = (jobData["siteAddress"] ??
            jobData["fullAddress"] ??
            jobData["location"] ??
            [
              siteStreet,
              siteCity,
              sitePostcode,
            ].where((part) => part.isNotEmpty).join(", "))
        .toString()
        .trim();

    /// 3. создаем application
    final applicationRef = await _db.collection('applications').add({
      "jobId": jobId,
      "workerId": userId,
      "applicantId": userId,
      "employerId": employerId,
      "status": "pending",
      "type": "single",
      "workerName": workerName,
      "members": [userId],
      "membersStatus": {userId: "pending"},

      // 🔥 ВАЖНО
      "jobTitle": (jobData["title"] ?? jobData["trade"] ?? "").toString(),
      "jobTrade": jobData["trade"] ?? "",
      "jobSite": jobData["site"] ?? "",
      "siteStreet": siteStreet,
      "siteCity": siteCity,
      "sitePostcode": sitePostcode,
      "siteCounty": siteCounty,
      "siteAddress": siteAddress,
      "fullAddress": siteAddress,

      "createdAt": FieldValue.serverTimestamp(),
      ...ApplicationActivityService.createdForEmployer(employerId.toString()),
    });

    /// 4. уведомление работодателю
    await notificationService.sendNotification(
      userId: employerId.toString(),
      title: "New application received",
      body: "$workerName applied for ${(jobData["trade"] ?? "your job")}",
      type: "application",
      applicationId: applicationRef.id,
      jobId: jobId,
      extra: {
        "targetType": "application",
        "targetId": applicationRef.id,
        "fromUserId": userId,
        "workerId": userId,
      },
    );
  }

  /// 🔥 APPLICATIONS (WORKER)
  Stream<List<Map<String, dynamic>>> getUserApplications(String userId) {
    return _db
        .collection('applications')
        .where('workerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data["id"] = doc.id;
        return data;
      }).toList();
    });
  }

  /// 🔥 APPLICATIONS (EMPLOYER)
  Stream<List<Map<String, dynamic>>> getEmployerApplications(
      String employerId) {
    return _db
        .collection('applications')
        .where('employerId', isEqualTo: employerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data["id"] = doc.id;
        return data;
      }).toList();
    });
  }

  /// 🔥 UPDATE STATUS
  Future<void> updateApplicationStatus(
      String applicationId, ApplicationStatus status) async {
    final doc = await _db.collection('applications').doc(applicationId).get();
    final data = doc.data() ?? {};

    await ApplicationActivityService.updateStatus(
      applicationId: applicationId,
      status: status.name,
      unreadFor: ApplicationActivityService.workerRecipients(data),
    );
  }

  /// 🔹 SAVE / UNSAVE
  Future<void> toggleSaveJob(String userId, String jobId, bool isSaved) async {
    final ref =
        _db.collection('saved_jobs').doc(userId).collection('jobs').doc(jobId);

    if (isSaved) {
      await ref.delete();
    } else {
      await ref.set({
        "savedAt": FieldValue.serverTimestamp(),
      });
    }
  }

  /// 🔥 STREAM SAVED JOB IDS
  Stream<Set<String>> getSavedJobsStream(String userId) {
    return _db
        .collection('saved_jobs')
        .doc(userId)
        .collection('jobs')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((e) => e.id).toSet();
    });
  }

  /// 🔹 FALLBACK
  Future<Set<String>> getSavedJobs(String userId) async {
    final snapshot =
        await _db.collection('saved_jobs').doc(userId).collection('jobs').get();

    return snapshot.docs.map((e) => e.id).toSet();
  }

  /// 🔹 RATING
  Future<double> getJobRating(String jobId) async {
    final snapshot =
        await _db.collection("reviews").where("jobId", isEqualTo: jobId).get();

    if (snapshot.docs.isEmpty) return 0;

    double total = 0;

    for (var d in snapshot.docs) {
      total += (d["rating"] ?? 0);
    }

    return total / snapshot.docs.length;
  }
}

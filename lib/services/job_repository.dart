import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/job.dart';
import 'notification_service.dart';

enum ApplicationStatus {
  pending,
  accepted,
  rejected,
}

class JobRepository {
  final _db = FirebaseFirestore.instance;
  final notificationService = NotificationService();

  /// 🔹 ВСЕ JOBS
  Stream<List<Job>> getJobs() {
    return _db.collection('jobs').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) {
            final data = doc.data();

            if (data["ownerId"] == null || data["ownerId"] == "") {
              return null;
            }

            return Job.fromFirestore(doc.id, data);
          })
          .whereType<Job>()
          .toList();
      ;
    });
  }

  /// 🔥 JOBS ПО РАБОТОДАТЕЛЮ (НОВОЕ)
  Stream<List<Job>> getJobsByOwner(String ownerId) {
    return _db
        .collection('jobs')
        .where('ownerId', isEqualTo: ownerId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Job.fromFirestore(doc.id, data);
      }).toList();
    });
  }

  /// 🔥 ПРОВЕРКА: УЖЕ ОТКЛИКНУЛСЯ?
  Future<bool> hasApplied(String jobId, String userId) async {
    final snapshot = await _db
        .collection('applications')
        .where('jobId', isEqualTo: jobId)
        .where('workerId', isEqualTo: userId)
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
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

    final workerName = jobData["workerName"] ?? "Worker";

    /// 3. создаем application
    await _db.collection('applications').add({
      "jobId": jobId,
      "workerId": userId,
      "employerId": employerId,
      "status": "pending",

      // 🔥 ВАЖНО
      "jobTitle": jobData["title"] ?? "",
      "jobTrade": jobData["trade"] ?? "",
      "jobSite": jobData["site"] ?? "",

      "createdAt": FieldValue.serverTimestamp(),
    });

    /// 4. уведомление работодателю
    await _db
        .collection('users')
        .doc(employerId)
        .collection('notifications')
        .add({
      "type": "application",
      "jobId": jobId,
      "fromUserId": userId,
      "createdAt": FieldValue.serverTimestamp(),
      "read": false,
    });
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
    await _db.collection('applications').doc(applicationId).update({
      "status": status.name,
    });
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

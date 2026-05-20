import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'application_activity_service.dart';

class OfferAcceptanceService {
  const OfferAcceptanceService._();

  static int applicationSlotCount(Map<String, dynamic> data) {
    final workersCount = data["workersCount"];
    if (workersCount is num && workersCount > 0) return workersCount.toInt();

    final members = data["members"];
    if (members is List && members.isNotEmpty) {
      return members.map((member) => member.toString()).toSet().length;
    }

    return 1;
  }

  static int readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? "") ?? 0;
  }

  static Future<bool> acceptOffer({
    required String applicationId,
    String? currentUserId,
  }) async {
    var accepted = false;
    final db = FirebaseFirestore.instance;
    String? acceptedJobId;

    await db.runTransaction((transaction) async {
      final appRef = db.collection("applications").doc(applicationId);
      final appSnap = await transaction.get(appRef);
      if (!appSnap.exists) return;

      final appData = appSnap.data() as Map<String, dynamic>;
      final currentStatus = appData["status"]?.toString() ?? "";
      if (currentStatus == "accepted" || currentStatus == "offer_accepted") {
        return;
      }

      final jobId = appData["jobId"]?.toString() ?? "";
      if (jobId.isEmpty) throw Exception("missing_job_id");

      final jobRef = db.collection("jobs").doc(jobId);
      final jobSnap = await transaction.get(jobRef);
      if (!jobSnap.exists) throw Exception("job_not_found");

      final jobData = jobSnap.data() as Map<String, dynamic>;
      final positions = readInt(jobData["positions"]);
      final filled = readInt(jobData["filledPositions"]);
      final slotCount = applicationSlotCount(appData);
      final safePositions = positions <= 0 ? slotCount : positions;
      if (filled + slotCount > safePositions) {
        throw Exception("not_enough_positions");
      }

      transaction.update(appRef, {
        "status": "offer_accepted",
        "offerAcceptedAt": FieldValue.serverTimestamp(),
        "acceptedByWorkerId":
            currentUserId ?? FirebaseAuth.instance.currentUser?.uid,
        "applicationActivityAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
        "unreadFor": FieldValue.arrayUnion(
          ApplicationActivityService.employerRecipients(appData),
        ),
      });

      acceptedJobId = jobId;
      accepted = true;
    });

    if (accepted && acceptedJobId != null) {
      await _syncAcceptedSlotCounters(acceptedJobId!);
    }

    return accepted;
  }

  static Future<void> _syncAcceptedSlotCounters(String jobId) async {
    final db = FirebaseFirestore.instance;

    try {
      final jobRef = db.collection("jobs").doc(jobId);
      final jobSnap = await jobRef.get();
      if (!jobSnap.exists) return;

      final jobData = jobSnap.data() as Map<String, dynamic>;
      final positions = readInt(jobData["positions"]);
      final safePositions = positions <= 0 ? 1 : positions;

      final acceptedApps = await db
          .collection("applications")
          .where("jobId", isEqualTo: jobId)
          .where("status",
              whereIn: ["offer_accepted", "accepted", "hired"]).get();

      final filled = acceptedApps.docs.fold<int>(0, (total, doc) {
        return total + applicationSlotCount(doc.data());
      }).clamp(0, safePositions);

      await jobRef.update({
        "filledPositions": filled,
        "remainingPositions":
            (safePositions - filled).clamp(0, safePositions).toInt(),
        "updatedAt": FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Worker acceptance must not fail just because job counters are owner-managed
      // or temporarily unavailable.
      return;
    }
  }
}

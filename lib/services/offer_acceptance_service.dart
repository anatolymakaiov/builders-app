import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'application_activity_service.dart';

class OfferAcceptanceService {
  const OfferAcceptanceService._();

  static int applicationSlotCount(Map<String, dynamic> data) {
    final offerRaw = data["offer"];
    final offer = offerRaw is Map
        ? Map<String, dynamic>.from(offerRaw)
        : <String, dynamic>{};
    final selectedWorkerIds = offer["selectedWorkerIds"];
    if (selectedWorkerIds is List && selectedWorkerIds.isNotEmpty) {
      return selectedWorkerIds.map((id) => id.toString()).toSet().length;
    }

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

    await db.runTransaction((transaction) async {
      final appRef = db.collection("applications").doc(applicationId);
      final appSnap = await transaction.get(appRef);
      if (!appSnap.exists) return;

      final appData = appSnap.data() as Map<String, dynamic>;
      final currentStatus = appData["status"]?.toString() ?? "";
      final alreadyAccepted = currentStatus == "accepted" ||
          currentStatus == "offer_accepted" ||
          currentStatus == "hired" ||
          readInt(appData["acceptedSlotCount"]) > 0;
      if (alreadyAccepted) {
        return;
      }

      final offerRaw = appData["offer"];
      final offer = offerRaw is Map
          ? Map<String, dynamic>.from(offerRaw)
          : <String, dynamic>{};
      final selectedWorkerIds = offer["selectedWorkerIds"];
      if (selectedWorkerIds is List && selectedWorkerIds.isNotEmpty) {
        final currentId =
            currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
        final allowed =
            selectedWorkerIds.map((id) => id.toString()).contains(currentId);
        if (!allowed) throw Exception("worker_not_selected_for_offer");
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
      final nextFilled = filled + slotCount;
      if (nextFilled > safePositions) {
        throw Exception("not_enough_positions");
      }
      final remaining = (safePositions - nextFilled).clamp(0, safePositions);

      transaction.update(appRef, {
        "status": "offer_accepted",
        "offerAcceptedAt": FieldValue.serverTimestamp(),
        "acceptedByWorkerId":
            currentUserId ?? FirebaseAuth.instance.currentUser?.uid,
        "applicationActivityAt": FieldValue.serverTimestamp(),
        "acceptedSlotCount": slotCount,
        "updatedAt": FieldValue.serverTimestamp(),
        "unreadFor": ApplicationActivityService.employerRecipients(appData),
      });

      transaction.update(jobRef, {
        "filledPositions": nextFilled,
        "remainingPositions": remaining,
        "openSlots": remaining,
        "availablePositions": remaining,
        "lastAcceptedApplicationId": applicationId,
        "lastAcceptedCounterSyncAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });

      accepted = true;
    });

    return accepted;
  }
}

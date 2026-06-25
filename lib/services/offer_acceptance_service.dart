import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'application_activity_service.dart';

class OfferAcceptanceService {
  const OfferAcceptanceService._();

  static bool isAcceptedStatus(dynamic value) {
    final status = value?.toString().trim().toLowerCase() ?? "";
    return status == "accepted" ||
        status == "offer_accepted" ||
        status == "hired";
  }

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
      final currentStatus =
          appData["status"]?.toString().trim().toLowerCase() ?? "";
      final acceptedStatus = isAcceptedStatus(currentStatus);
      final slotCount = applicationSlotCount(appData);

      debugPrint(
        "OFFER ACCEPT SLOT UPDATE START "
        "jobId=${appData["jobId"] ?? ""} "
        "offerId=${appData["offerId"] ?? ""} "
        "applicationId=$applicationId "
        "previousStatus=$currentStatus "
        "newStatus=offer_accepted "
        "acceptedCount=$slotCount",
      );

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
      final appliedIdsRaw = jobData["slotDecrementApplicationIds"];
      final appliedIds = appliedIdsRaw is List
          ? appliedIdsRaw.map((id) => id.toString()).toSet()
          : <String>{};
      final alreadyApplied = appData["slotDecrementApplied"] == true ||
          appliedIds.contains(applicationId);
      if (alreadyApplied) {
        debugPrint(
          "OFFER ACCEPT SLOT UPDATE SKIPPED "
          "applicationId=$applicationId "
          "reason=slot_decrement_already_applied",
        );
        return;
      }

      if (acceptedStatus) {
        debugPrint(
          "OFFER ACCEPT SLOT UPDATE RECOVERING "
          "applicationId=$applicationId "
          "reason=accepted_status_without_slot_marker",
        );
      }

      final positions = readInt(jobData["positions"]);
      final filled = readInt(
        jobData["filledPositions"] ??
            jobData["acceptedSlotTotal"] ??
            jobData["hiredCount"],
      );
      final safePositions = positions <= 0 ? slotCount : positions;
      final nextFilled = filled + slotCount;
      if (nextFilled > safePositions) {
        debugPrint(
          "OFFER ACCEPT SLOT UPDATE SKIPPED "
          "applicationId=$applicationId "
          "reason=not_enough_positions "
          "filled=$filled "
          "acceptedCount=$slotCount "
          "positions=$safePositions",
        );
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
        "slotDecrementApplied": true,
        "slotDecrementAppliedAt": FieldValue.serverTimestamp(),
        "slotDecrementJobId": jobId,
        "updatedAt": FieldValue.serverTimestamp(),
        "unreadFor": ApplicationActivityService.employerRecipients(appData),
      });

      transaction.update(jobRef, {
        "filledPositions": nextFilled,
        "remainingPositions": remaining,
        "openSlots": remaining,
        "availablePositions": remaining,
        "availableSlots": remaining,
        "remainingSlots": remaining,
        "positionsAvailable": remaining,
        "acceptedOffersCount": FieldValue.increment(1),
        "hiredCount": nextFilled,
        "acceptedSlotTotal": nextFilled,
        "slotDecrementApplicationIds": FieldValue.arrayUnion([applicationId]),
        "lastAcceptedApplicationId": applicationId,
        "lastAcceptedCounterSyncAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });

      debugPrint(
        "OFFER ACCEPT SLOT UPDATE SUCCESS "
        "jobId=$jobId "
        "oldAvailable=${(safePositions - filled).clamp(0, safePositions)} "
        "newAvailable=$remaining "
        "totalSlots=$safePositions",
      );
      accepted = true;
    });

    return accepted;
  }
}

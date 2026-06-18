import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ModerationHoldService {
  ModerationHoldService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const suspensionTitle = "PROFILE TEMPORARILY SUSPENDED";
  static const suspensionMessage = "Please contact Administrator.";
  static const suspensionSnackBarMessage =
      "Your profile is temporarily suspended.\nPlease contact Administrator.";

  static bool isProfileHeld(Map<String, dynamic>? data) {
    if (data == null) return false;
    final status = data["status"]?.toString().toLowerCase().trim() ?? "";
    return data["moderationHold"] == true ||
        data["profileSuspended"] == true ||
        data["profileHold"] == true ||
        data["accountOnHold"] == true ||
        status == "suspended" ||
        status == "on_hold";
  }

  static bool isJobHeld(Map<String, dynamic>? data) {
    if (data == null) return false;
    final status = data["status"]?.toString().toLowerCase().trim() ?? "";
    final moderation =
        data["moderationStatus"]?.toString().toLowerCase().trim() ?? "";
    return data["moderationHold"] == true ||
        data["vacancyHold"] == true ||
        data["jobSuspended"] == true ||
        status == "suspended" ||
        status == "on_hold" ||
        moderation == "on_hold";
  }

  static String holdMessage(Map<String, dynamic>? data) {
    final message = data?["holdMessage"]?.toString().trim();
    if (message != null && message.isNotEmpty) return message;
    final reason = data?["holdReason"]?.toString().trim();
    if (reason != null && reason.isNotEmpty) return reason;
    return "Profile temporarily suspended. Please check Alerts.";
  }

  Future<bool> isCurrentUserHeld() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final snap = await _firestore.collection("users").doc(uid).get();
    return isProfileHeld(snap.data());
  }

  Future<Map<String, dynamic>?> currentUserHoldData() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final snap = await _firestore.collection("users").doc(uid).get();
    return snap.data();
  }

  Future<bool> ensureCurrentUserNotHeld(BuildContext context) async {
    final data = await currentUserHoldData();
    if (!context.mounted) return false;
    if (!isProfileHeld(data)) return true;
    showHoldSnackBar(context);
    return false;
  }

  static void showHoldSnackBar(
    BuildContext context,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(suspensionSnackBarMessage)),
    );
  }

  static void showSafeSnackBar(BuildContext context, String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    });
  }

  Future<void> holdUser({
    required String targetUserId,
    required String role,
    required String message,
  }) async {
    final adminId = _auth.currentUser?.uid ?? "admin";
    final trimmedMessage = message.trim();
    if (targetUserId.trim().isEmpty || trimmedMessage.isEmpty) return;

    await _firestore.collection("users").doc(targetUserId).set({
      "moderationHold": true,
      "profileSuspended": true,
      "holdReason": trimmedMessage,
      "holdMessage": trimmedMessage,
      "heldAt": FieldValue.serverTimestamp(),
      "heldBy": adminId,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> sendAdminHoldMessage({
    required String userId,
    required String role,
    required String title,
    required String message,
    required String relatedTargetType,
    required String relatedTargetId,
  }) async {
    if (userId.trim().isEmpty || message.trim().isEmpty) return;

    final now = FieldValue.serverTimestamp();
    final adminId = _auth.currentUser?.uid ?? "admin";
    final threadRef = _firestore.collection("message_threads").doc();
    final messageRef = _firestore.collection("admin_messages").doc();
    final userSnap = await _firestore.collection("users").doc(userId).get();
    final userData = userSnap.data() ?? <String, dynamic>{};
    final receiverName = (userData["companyName"] ??
            userData["name"] ??
            userData["displayName"] ??
            userData["email"] ??
            userId)
        .toString();

    final batch = _firestore.batch();
    final payload = <String, dynamic>{
      "threadId": threadRef.id,
      "direction": "outgoing",
      "senderId": adminId,
      "senderName": "Admin",
      "senderRole": "admin",
      "receiverId": userId,
      "receiverName": receiverName,
      "receiverRole": role,
      "recipientId": userId,
      "recipientRole": role,
      "threadParticipants": ["admin", userId],
      "audienceType": role,
      "canReply": true,
      "subject": title.trim(),
      "message": message.trim(),
      "type": "admin_message",
      "relatedTargetType": relatedTargetType,
      "relatedTargetId": relatedTargetId,
      "readByAdmin": true,
      "readByReceiver": false,
      "important": true,
      "deletedByAdmin": false,
      "deletedByReceiver": false,
      "deletedBySender": false,
      "attachments": const <Map<String, dynamic>>[],
      "hasAttachments": false,
      "createdAt": now,
    };

    batch.set(messageRef, payload);
    batch.set(
        threadRef,
        {
          "subject": title.trim(),
          "participants": ["admin", userId],
          "lastMessage": message.trim(),
          "lastMessageAt": now,
          "lastSenderId": adminId,
          "unreadForAdmin": 0,
          "updatedAt": now,
        },
        SetOptions(merge: true));

    final inboxRef = _firestore
        .collection("users")
        .doc(userId)
        .collection("admin_inbox")
        .doc();
    final legacyPayload = {
      "userId": userId,
      "title": title.trim(),
      "message": message.trim(),
      "type": "admin_message",
      "targetType": "admin_message",
      "targetId": threadRef.id,
      "audience": role,
      "audienceType": role,
      "canReply": true,
      "read": false,
      "threadId": threadRef.id,
      "adminMessageId": messageRef.id,
      "relatedTargetType": relatedTargetType,
      "relatedTargetId": relatedTargetId,
      "createdAt": now,
    };
    batch.set(inboxRef, legacyPayload);
    batch.set(_firestore.collection("admin_inbox_messages").doc(), {
      ...legacyPayload,
      "targetUserId": userId,
      "recipientCount": 1,
    });

    final notificationRef = _firestore
        .collection("users")
        .doc(userId)
        .collection("notifications")
        .doc();
    batch.set(notificationRef, {
      "notificationId": notificationRef.id,
      "userId": userId,
      "type": "admin_message",
      "category": "admin",
      "targetType": "admin_message",
      "targetId": threadRef.id,
      "threadId": threadRef.id,
      "adminMessageId": messageRef.id,
      "title": title.trim(),
      "message": message.trim(),
      "read": false,
      "badgeEligible": true,
      "pushEligible": true,
      "createdAt": now,
    });

    await batch.commit();
  }

  Future<void> restoreUser(String targetUserId) async {
    if (targetUserId.trim().isEmpty) return;
    await _firestore.collection("users").doc(targetUserId).set({
      "moderationHold": false,
      "profileSuspended": false,
      "profileHold": false,
      "accountOnHold": false,
      "holdReason": FieldValue.delete(),
      "holdMessage": FieldValue.delete(),
      "restoredAt": FieldValue.serverTimestamp(),
      "restoredBy": _auth.currentUser?.uid ?? "admin",
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> holdJob({
    required String jobId,
    required String message,
  }) async {
    final trimmedMessage = message.trim();
    if (jobId.trim().isEmpty || trimmedMessage.isEmpty) return;

    final ref = _firestore.collection("jobs").doc(jobId);
    final snap = await ref.get();
    final data = snap.data() ?? <String, dynamic>{};
    await ref.set({
      "moderationHold": true,
      "vacancyHold": true,
      "statusBeforeHold": data["status"],
      "moderationStatusBeforeHold": data["moderationStatus"],
      "status": "on_hold",
      "moderationStatus": "on_hold",
      "holdReason": trimmedMessage,
      "holdMessage": trimmedMessage,
      "heldAt": FieldValue.serverTimestamp(),
      "heldBy": _auth.currentUser?.uid ?? "admin",
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> restoreJob(String jobId) async {
    if (jobId.trim().isEmpty) return;
    final ref = _firestore.collection("jobs").doc(jobId);
    final snap = await ref.get();
    final data = snap.data() ?? <String, dynamic>{};
    final previousStatus = data["statusBeforeHold"]?.toString().trim();
    final previousModeration =
        data["moderationStatusBeforeHold"]?.toString().trim();

    await ref.set({
      "moderationHold": false,
      "vacancyHold": false,
      "jobSuspended": false,
      if (previousStatus != null && previousStatus.isNotEmpty)
        "status": previousStatus,
      if (previousModeration != null && previousModeration.isNotEmpty)
        "moderationStatus": previousModeration,
      "holdReason": FieldValue.delete(),
      "holdMessage": FieldValue.delete(),
      "restoredAt": FieldValue.serverTimestamp(),
      "restoredBy": _auth.currentUser?.uid ?? "admin",
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

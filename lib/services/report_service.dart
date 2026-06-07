import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'notification_service.dart';

class ReportService {
  static Future<void> showReportDialog(
    BuildContext context, {
    required String type,
    String? againstUserId,
    String? jobId,
    String? applicationId,
    String? chatId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final message = await showDialog<String>(
      context: context,
      builder: (_) => const _ReportDialog(),
    );
    if (message == null || message.isEmpty) return;

    try {
      final userSnap = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();
      final userData = userSnap.data() ?? <String, dynamic>{};
      final senderName = (userData["companyName"] ??
              userData["name"] ??
              userData["displayName"] ??
              user.displayName ??
              "")
          .toString()
          .trim();

      final reportRef = FirebaseFirestore.instance.collection("reports").doc();
      final threadId = await _createAdminInboxThreadForReport(
        reportId: reportRef.id,
        reportType: type,
        reporterId: user.uid,
        reporterData: userData,
        reporterName: senderName.isNotEmpty ? senderName : "User",
        message: message,
        againstUserId: againstUserId,
        jobId: jobId,
        applicationId: applicationId,
        chatId: chatId,
      );
      await reportRef.set({
        "fromUserId": user.uid,
        "userId": user.uid,
        "senderId": user.uid,
        "senderRole": userData["role"]?.toString() ?? "",
        if (senderName.isNotEmpty) "senderName": senderName,
        if ((user.email ?? "").trim().isNotEmpty) "senderEmail": user.email,
        if (againstUserId != null && againstUserId.isNotEmpty)
          "againstUserId": againstUserId,
        if (jobId != null && jobId.isNotEmpty) "jobId": jobId,
        if (applicationId != null && applicationId.isNotEmpty)
          "applicationId": applicationId,
        if (chatId != null && chatId.isNotEmpty) "chatId": chatId,
        "type": type,
        "message": message,
        "status": "open",
        "readByAdmin": false,
        "viewedByAdmin": false,
        "source": "chat",
        "threadId": threadId,
        "adminMessageThreadId": threadId,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });

      unawaited(_notifyReportedEmployerIfNeeded(
        againstUserId: againstUserId,
        reportId: reportRef.id,
        reportType: type,
      ));

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Report submitted successfully")),
      );
    } catch (e) {
      debugPrint("REPORT SUBMIT ERROR: $e");
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not submit report. Please try again."),
        ),
      );
    }
  }

  static Future<void> _notifyReportedEmployerIfNeeded({
    required String? againstUserId,
    required String reportId,
    required String reportType,
  }) async {
    if (againstUserId == null || againstUserId.isEmpty) return;

    try {
      final targetSnap = await FirebaseFirestore.instance
          .collection("users")
          .doc(againstUserId)
          .get();
      final targetRole = targetSnap.data()?["role"]?.toString() ?? "";
      if (targetRole != "employer") return;

      await NotificationService().notifyEmployerReportSubmitted(
        employerId: againstUserId,
        reportId: reportId,
        reportType: reportType,
      );
    } catch (e) {
      debugPrint("REPORT NOTIFICATION ERROR: $e");
    }
  }

  static Future<String> _createAdminInboxThreadForReport({
    required String reportId,
    required String reportType,
    required String reporterId,
    required Map<String, dynamic> reporterData,
    required String reporterName,
    required String message,
    String? againstUserId,
    String? jobId,
    String? applicationId,
    String? chatId,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final threadRef = firestore.collection("message_threads").doc();
    final messageRef = firestore.collection("admin_messages").doc();
    final now = FieldValue.serverTimestamp();
    final reporterRole = reporterData["role"]?.toString() ?? "";
    final subject = "Report: ${_reportTypeLabel(reportType)}";

    final batch = firestore.batch();
    batch.set(messageRef, {
      "threadId": threadRef.id,
      "direction": "incoming",
      "senderId": reporterId,
      "senderName": reporterName.trim().isNotEmpty ? reporterName : "User",
      "senderRole": reporterRole,
      "receiverId": "admin",
      "receiverName": "Admin",
      "receiverRole": "admin",
      "recipientId": "admin",
      "recipientRole": "admin",
      "threadParticipants": [reporterId, "admin"],
      "audienceType": "specific_admin",
      "canReply": true,
      "subject": subject,
      "message": message,
      "type": "report",
      "reportType": reportType,
      "relatedReportId": reportId,
      "relatedTargetType": "report",
      "relatedTargetId": reportId,
      if (againstUserId != null && againstUserId.isNotEmpty)
        "againstUserId": againstUserId,
      if (jobId != null && jobId.isNotEmpty) "jobId": jobId,
      if (applicationId != null && applicationId.isNotEmpty)
        "applicationId": applicationId,
      if (chatId != null && chatId.isNotEmpty) "chatId": chatId,
      "readByAdmin": false,
      "readByReceiver": true,
      "important": false,
      "deletedByAdmin": false,
      "deletedByReceiver": false,
      "deletedBySender": false,
      "attachments": const <Map<String, dynamic>>[],
      "hasAttachments": false,
      "createdAt": now,
    });
    batch.set(threadRef, {
      "subject": subject,
      "participants": [reporterId, "admin"],
      "createdBy": reporterId,
      "userId": reporterId,
      "userRole": reporterRole,
      "threadType": "report",
      "lastMessage": message,
      "lastMessageAt": now,
      "lastSenderId": reporterId,
      "unreadForAdmin": 1,
      "relatedReportId": reportId,
      "updatedAt": now,
    });
    batch.set(
      firestore.collection("unread_counters").doc("admin"),
      {
        "unreadInbox": FieldValue.increment(1),
        "updatedAt": now,
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    return threadRef.id;
  }

  static String _reportTypeLabel(String type) {
    return type
        .replaceAll("_", " ")
        .split(" ")
        .where((word) => word.trim().isNotEmpty)
        .map((word) => "${word[0].toUpperCase()}${word.substring(1)}")
        .join(" ");
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final message = controller.text.trim();
    if (message.isEmpty) return;
    Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Report"),
      content: TextField(
        controller: controller,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: "Message",
          hintText: "Describe the issue",
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: submit,
          child: const Text("Submit"),
        ),
      ],
    );
  }
}

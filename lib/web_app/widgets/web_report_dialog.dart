import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'web_design_components.dart';

Future<void> showWebReportDialog(BuildContext context,
    {required String type,
    String? againstUserId,
    String? jobId,
    String? applicationId,
    String? chatId}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final message = await showDialog<String>(
      context: context,
      builder: (_) =>
          const WebTextDialog(title: 'Report', label: 'Describe the issue'));
  if (message == null || message.trim().isEmpty) return;
  try {
    final data = (await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get())
            .data() ??
        {};
    final ref = FirebaseFirestore.instance.collection('reports').doc();
    await _WebReportWriter._createAdminInboxThreadForReport(
        reportId: ref.id,
        reportRef: ref,
        reportType: type,
        reporterId: user.uid,
        reporterData: data,
        reporterName:
            (data['role'] == 'employer' ? data['companyName'] : data['name'])
                    ?.toString() ??
                'User',
        reporterEmail: user.email,
        message: message.trim(),
        againstUserId: againstUserId,
        jobId: jobId,
        applicationId: applicationId,
        chatId: chatId);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Report sent')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit report: $error')));
    }
  }
}

class WebTextDialog extends StatefulWidget {
  const WebTextDialog(
      {super.key, required this.title, required this.label, this.initial = ''});
  final String title;
  final String label;
  final String initial;
  @override
  State<WebTextDialog> createState() => _WebTextDialogState();
}

class _WebTextDialogState extends State<WebTextDialog> {
  late final text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: WebDialogScrollArea(
            preferredWidth: 420,
            child: TextField(
                controller: text,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(labelText: widget.label))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (text.text.trim().isNotEmpty) {
                  Navigator.pop(context, text.text.trim());
                }
              },
              child: const Text('Submit')),
        ],
      );
}

class _WebReportWriter {
  static Future<String> _createAdminInboxThreadForReport({
    required String reportId,
    required DocumentReference<Map<String, dynamic>> reportRef,
    required String reportType,
    required String reporterId,
    required Map<String, dynamic> reporterData,
    required String reporterName,
    String? reporterEmail,
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
    batch.set(reportRef, {
      "fromUserId": reporterId,
      "userId": reporterId,
      "senderId": reporterId,
      "senderRole": reporterRole,
      if (reporterName.trim().isNotEmpty) "senderName": reporterName.trim(),
      if ((reporterEmail ?? "").trim().isNotEmpty)
        "senderEmail": reporterEmail!.trim(),
      if (againstUserId != null && againstUserId.isNotEmpty)
        "againstUserId": againstUserId,
      if (jobId != null && jobId.isNotEmpty) "jobId": jobId,
      if (applicationId != null && applicationId.isNotEmpty)
        "applicationId": applicationId,
      if (chatId != null && chatId.isNotEmpty) "chatId": chatId,
      "type": reportType,
      "message": message,
      "status": "open",
      "readByAdmin": false,
      "viewedByAdmin": false,
      "source": "chat",
      "threadId": threadRef.id,
      "adminMessageThreadId": threadRef.id,
      "createdAt": now,
      "updatedAt": now,
    });
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

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

    final controller = TextEditingController();

    final message = await showDialog<String>(
      context: context,
      builder: (context) {
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
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text("Submit"),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (message == null || message.isEmpty) return;

    final reportRef =
        await FirebaseFirestore.instance.collection("reports").add({
      "fromUserId": user.uid,
      if (againstUserId != null && againstUserId.isNotEmpty)
        "againstUserId": againstUserId,
      if (jobId != null && jobId.isNotEmpty) "jobId": jobId,
      if (applicationId != null && applicationId.isNotEmpty)
        "applicationId": applicationId,
      if (chatId != null && chatId.isNotEmpty) "chatId": chatId,
      "type": type,
      "message": message,
      "status": "open",
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    });

    if (againstUserId != null && againstUserId.isNotEmpty) {
      final targetSnap = await FirebaseFirestore.instance
          .collection("users")
          .doc(againstUserId)
          .get();
      final targetRole = targetSnap.data()?["role"]?.toString() ?? "";
      if (targetRole != "employer") {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Report submitted")),
        );
        return;
      }

      await NotificationService().notifyEmployerReportSubmitted(
        employerId: againstUserId,
        reportId: reportRef.id,
        reportType: type,
      );
    }

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Report submitted")),
    );
  }
}

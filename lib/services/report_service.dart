import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Report submitted")),
    );
  }
}

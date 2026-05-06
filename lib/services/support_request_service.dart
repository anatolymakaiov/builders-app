import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SupportRequestService {
  static const workerRequestTypes = {
    "participant_complaint": "Complaint about another participant",
    "employer_complaint": "Complaint about employer/company",
    "technical_issue": "Technical issue with app/site",
    "job_ad_complaint": "Complaint about advertisement/job post",
  };

  static const employerRequestTypes = {
    "payment": "Payment",
    "job_publishing": "Job publishing",
    "job_extension": "Job extension",
    "job_pause_removal": "Job pause/removal",
    "technical_issue": "Technical issue",
    "other": "Other",
  };

  static Future<void> showSupportDialog(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();
    if (!context.mounted) return;

    final userRole = userDoc.data()?["role"]?.toString().toLowerCase() ?? "";
    final requestTypes =
        userRole == "worker" ? workerRequestTypes : employerRequestTypes;

    final controller = TextEditingController();
    var selectedType = requestTypes.keys.first;

    final result = await showDialog<({String type, String message})>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Support request"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: "Type"),
                    items: requestTypes.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => selectedType = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: "Message",
                      hintText: "Describe what you need help with",
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(
                    context,
                    (
                      type: selectedType,
                      message: controller.text.trim(),
                    ),
                  ),
                  child: const Text("Submit"),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    if (result == null || result.message.isEmpty) return;

    await FirebaseFirestore.instance.collection("support_requests").add({
      "userId": user.uid,
      "userRole": userRole,
      "type": result.type,
      "typeLabel": requestTypes[result.type] ?? result.type,
      "message": result.message,
      "status": "open",
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    });

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Support request submitted")),
    );
  }
}

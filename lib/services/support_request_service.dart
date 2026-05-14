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

    final result = await showDialog<({String type, String message})>(
      context: context,
      builder: (_) => _SupportRequestDialog(requestTypes: requestTypes),
    );

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

class _SupportRequestDialog extends StatefulWidget {
  final Map<String, String> requestTypes;

  const _SupportRequestDialog({
    required this.requestTypes,
  });

  @override
  State<_SupportRequestDialog> createState() => _SupportRequestDialogState();
}

class _SupportRequestDialogState extends State<_SupportRequestDialog> {
  late String selectedType;
  late final TextEditingController controller;
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    selectedType = widget.requestTypes.keys.first;
    controller = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void closeWithResult() {
    final message = controller.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please describe your request")),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    submitting = true;
    Navigator.of(context).pop((type: selectedType, message: message));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = screenWidth < 440 ? screenWidth - 48 : 420.0;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: const Text("Support request"),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: "Type"),
                selectedItemBuilder: (context) {
                  return widget.requestTypes.values.map((label) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList();
                },
                items: widget.requestTypes.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          entry.value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: submitting
                    ? null
                    : (value) {
                        if (value == null || !mounted) return;
                        setState(() => selectedType = value);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                enabled: !submitting,
                maxLines: 5,
                minLines: 3,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: "Message",
                  hintText: "Describe what you need help with",
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: submitting ? null : () => Navigator.of(context).pop(null),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: submitting ? null : closeWithResult,
          child: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("Submit"),
        ),
      ],
    );
  }
}
